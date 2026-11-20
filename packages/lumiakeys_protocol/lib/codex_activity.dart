/// The only data sent to a paired device about the monitored Codex chat.
enum CodexActivityStatus { idle, thinking, complete, needsInput, error }

const codexActivityCapability = 'codex-activity-v1';
const codexActivityPath = '/chatgpt-activity';
