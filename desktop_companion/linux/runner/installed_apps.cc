#include "installed_apps.h"
#include <gio/gdesktopappinfo.h>
#include <gtk/gtk.h>
#include <cstring>

namespace {
constexpr gsize kMaxText = 4096;
constexpr gsize kMaxDiscoveryBytes = 2 * 1024 * 1024;
constexpr guint kMaxApplications = 2000;

bool valid_text(const gchar* value) {
  if (!value || !*value || strlen(value) > kMaxText || !g_utf8_validate(value, -1, nullptr)) return false;
  for (const guchar* p = reinterpret_cast<const guchar*>(value); *p; ++p) {
    if (*p < 32 || *p == 127) return false;
  }
  return true;
}
void fail(FlMethodCall* call) {
  fl_method_call_respond_error(call, "registered_app_unavailable", "The registered application is unavailable.", nullptr, nullptr);
}
void set_optional(FlValue* map, const gchar* key, const gchar* value) {
  if (valid_text(value)) fl_value_set_string_take(map, key, fl_value_new_string(value));
}

void discover_worker(GTask* task, gpointer, gpointer, GCancellable*) {
  GList* applications = g_app_info_get_all();
  g_autoptr(FlValue) values = fl_value_new_list();
  gsize bytes = 0;
  guint count = 0;
  const gint64 deadline = g_get_monotonic_time() + 8 * G_TIME_SPAN_SECOND;
  bool failed = false;
  for (GList* cursor = applications; cursor; cursor = cursor->next) {
    if (g_get_monotonic_time() > deadline) { failed = true; break; }
    GAppInfo* app = G_APP_INFO(cursor->data);
    if (!G_IS_DESKTOP_APP_INFO(app) || !g_app_info_should_show(app)) continue;
    const gchar* identity = g_app_info_get_id(app);
    const gchar* name = g_app_info_get_display_name(app);
    const gchar* locator = g_desktop_app_info_get_filename(G_DESKTOP_APP_INFO(app));
    if (!valid_text(identity) || !valid_text(name) || !valid_text(locator) || !g_path_is_absolute(locator)) continue;
    const gchar* executable = g_app_info_get_executable(app);
    const gchar* wm_class = g_desktop_app_info_get_startup_wm_class(G_DESKTOP_APP_INFO(app));
    g_autofree gchar* icon = g_app_info_get_icon(app) ? g_icon_to_string(g_app_info_get_icon(app)) : nullptr;
    // Conservative JSON escaping allowance; never silently return a partial list.
    bytes += 256 + 2 * (strlen(identity) + strlen(name) + strlen(locator));
    const gchar* optional_values[] = {executable, wm_class, icon};
    for (const gchar* optional : optional_values) {
      if (valid_text(optional)) bytes += 2 * strlen(optional);
    }
    if (++count > kMaxApplications || bytes > kMaxDiscoveryBytes || g_get_monotonic_time() > deadline) {
      failed = true; break;
    }
    FlValue* item = fl_value_new_map();
    fl_value_set_string_take(item, "identity", fl_value_new_string(identity));
    fl_value_set_string_take(item, "name", fl_value_new_string(name));
    fl_value_set_string_take(item, "locator", fl_value_new_string(locator));
    set_optional(item, "executablePath", executable);
    set_optional(item, "startupWMClass", wm_class);
    set_optional(item, "iconKey", icon);
    fl_value_append_take(values, item);
  }
  g_list_free_full(applications, g_object_unref);
  if (failed) {
    g_task_return_new_error(task, G_IO_ERROR, G_IO_ERROR_FAILED, "Installed application scan exceeded its bound.");
  } else {
    g_task_return_pointer(task, fl_value_ref(values), [](gpointer value) {
      fl_value_unref(static_cast<FlValue*>(value));
    });
  }
}
void discover_complete(GObject*, GAsyncResult* async, gpointer data) {
  FlMethodCall* call = FL_METHOD_CALL(data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(FlValue) values = static_cast<FlValue*>(g_task_propagate_pointer(G_TASK(async), &error));
  if (error) fail(call); else fl_method_call_respond_success(call, values, nullptr);
  g_object_unref(call);
}

bool get_target(FlMethodCall* call, const gchar** kind, const gchar** locator) {
  FlValue* args = fl_method_call_get_args(call);
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP || fl_value_get_length(args) != 2) return false;
  FlValue* kind_value = fl_value_lookup_string(args, "kind");
  FlValue* path_value = fl_value_lookup_string(args, "locator");
  if (!kind_value || !path_value || fl_value_get_type(kind_value) != FL_VALUE_TYPE_STRING || fl_value_get_type(path_value) != FL_VALUE_TYPE_STRING) return false;
  *kind = fl_value_get_string(kind_value);
  *locator = fl_value_get_string(path_value);
  if (!valid_text(*locator) || !g_path_is_absolute(*locator) || !g_file_test(*locator, G_FILE_TEST_IS_REGULAR)) return false;
  if (g_str_equal(*kind, "linuxDesktopEntry")) return g_str_has_suffix(*locator, ".desktop");
  return g_str_equal(*kind, "linuxExecutable") && g_file_test(*locator, G_FILE_TEST_IS_EXECUTABLE);
}

GDesktopAppInfo* desktop_info(const gchar* kind, const gchar* locator) {
  if (!g_str_equal(kind, "linuxDesktopEntry")) return nullptr;
  GDesktopAppInfo* app = g_desktop_app_info_new_from_filename(locator);
  if (app && g_desktop_app_info_get_is_hidden(app)) { g_object_unref(app); return nullptr; }
  return app;
}
void launch(FlMethodCall* call, const gchar* kind, const gchar* locator) {
  g_autoptr(GError) error = nullptr;
  gboolean accepted = FALSE;
  if (g_str_equal(kind, "linuxDesktopEntry")) {
    g_autoptr(GDesktopAppInfo) app = desktop_info(kind, locator);
    if (!app) { fail(call); return; }
    g_autoptr(GAppLaunchContext) context = g_app_launch_context_new();
    // GIO owns Exec field codes, Terminal and DBus activation; no shell parser.
    accepted = g_app_info_launch(G_APP_INFO(app), nullptr, context, &error);
  } else {
    gchar* argv[] = {const_cast<gchar*>(locator), nullptr};
    accepted = g_spawn_async(nullptr, argv, nullptr, G_SPAWN_DEFAULT, nullptr, nullptr, nullptr, &error);
  }
  if (!accepted) fail(call);
  else {
    g_autoptr(FlValue) success = fl_value_new_bool(true);
    fl_method_call_respond_success(call, success, nullptr);
  }
}
void icon(FlMethodCall* call, const gchar* kind, const gchar* locator) {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDesktopAppInfo) app = desktop_info(kind, locator);
  g_autoptr(GFile) file = nullptr;
  g_autoptr(GFileInfo) info = nullptr;
  GIcon* value = nullptr;
  if (app) value = g_app_info_get_icon(G_APP_INFO(app));
  else if (!g_str_equal(kind, "linuxDesktopEntry")) {
    file = g_file_new_for_path(locator);
    info = g_file_query_info(file, G_FILE_ATTRIBUTE_STANDARD_ICON, G_FILE_QUERY_INFO_NONE, nullptr, &error);
    if (info) value = g_file_info_get_icon(info);
  }
  if (!value || (G_IS_FILE_ICON(value) && !g_file_is_native(g_file_icon_get_file(G_FILE_ICON(value))))) {
    fl_method_call_respond_success(call, nullptr, nullptr); return;
  }
  g_autoptr(GtkIconInfo) themed = gtk_icon_theme_lookup_by_gicon(gtk_icon_theme_get_default(), value, 128, GTK_ICON_LOOKUP_FORCE_SIZE);
  if (!themed) { fl_method_call_respond_success(call, nullptr, nullptr); return; }
  g_autoptr(GdkPixbuf) image = gtk_icon_info_load_icon(themed, nullptr);
  if (!image || gdk_pixbuf_get_width(image) > 512 || gdk_pixbuf_get_height(image) > 512) {
    fl_method_call_respond_success(call, nullptr, nullptr); return;
  }
  gchar* png = nullptr; gsize length = 0;
  if (!gdk_pixbuf_save_to_buffer(image, &png, &length, "png", nullptr, "compression", "9", nullptr) || length > 64 * 1024) {
    g_free(png); fl_method_call_respond_success(call, nullptr, nullptr); return;
  }
  g_autoptr(FlValue) bytes = fl_value_new_uint8_list(reinterpret_cast<const uint8_t*>(png), length);
  g_free(png);
  fl_method_call_respond_success(call, bytes, nullptr);
}
void method(FlMethodChannel*, FlMethodCall* call, gpointer) {
  const gchar* name = fl_method_call_get_name(call);
  if (g_str_equal(name, "discover")) {
    GTask* task = g_task_new(nullptr, nullptr, discover_complete, g_object_ref(call));
    g_task_run_in_thread(task, discover_worker); g_object_unref(task); return;
  }
  if (!g_str_equal(name, "launch") && !g_str_equal(name, "icon")) {
    fl_method_call_respond_not_implemented(call, nullptr); return;
  }
  const gchar* kind = nullptr; const gchar* locator = nullptr;
  if (!get_target(call, &kind, &locator)) { fail(call); return; }
  if (g_str_equal(name, "launch")) launch(call, kind, locator); else icon(call, kind, locator);
}
}  // namespace
FlMethodChannel* lumiakey_installed_apps_register(FlBinaryMessenger* messenger) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(messenger, "lumiakeys/installed_apps", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method, nullptr, nullptr);
  return channel;
}
