CREATE TABLE IF NOT EXISTS diagnostic_errors (
    event_id VARCHAR(36) PRIMARY KEY CHECK (length(event_id) = 36),
    occurred_at_ms BIGINT NOT NULL CHECK (occurred_at_ms >= 0),
    last_occurred_at_ms BIGINT NOT NULL CHECK (last_occurred_at_ms >= occurred_at_ms),
    app_version VARCHAR(11) NOT NULL CHECK (app_version ~ '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'),
    app_build INTEGER NOT NULL CHECK (app_build BETWEEN 0 AND 1000000000),
    edition VARCHAR(4) NOT NULL CHECK (edition = 'full'),
    platform VARCHAR(7) NOT NULL CHECK (platform IN ('android', 'ios')),
    code VARCHAR(40) NOT NULL CHECK (code IN (
        'connectionUnavailable','connectionTimeout','connectionAuthenticationFailed','connectionProtocolInvalid',
        'applicationActivationFailed','shortcutDeliveryFailed','pointerDeliveryFailed','iconDownloadFailed',
        'iconDataInvalid','configurationLoadFailed','configurationInvalid','configurationSaveFailed',
        'storageReadFailed','storageWriteFailed','bluetoothUnavailable','bluetoothPermissionDenied',
        'bluetoothConnectionFailed','bluetoothInputFailed','platformUnavailable','runtimeFailure')),
    repeat_count INTEGER NOT NULL CHECK (repeat_count BETWEEN 1 AND 1000000)
);
CREATE INDEX IF NOT EXISTS diagnostic_errors_retention ON diagnostic_errors(last_occurred_at_ms, event_id);
