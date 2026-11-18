/// Product capabilities are chosen at build time, never by the connection state.
enum AppEdition { regular, lite }

const buildEdition =
    String.fromEnvironment('LUMIAKEY_EDITION', defaultValue: 'regular') ==
        'lite'
    ? AppEdition.lite
    : AppEdition.regular;
