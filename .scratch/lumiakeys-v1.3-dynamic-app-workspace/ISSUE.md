# LumiaKeys V1.3 — Dynamic App Workspace

- Status: `ready-for-agent`
- Type: Incremental product feature
- Source of truth: [`docs/V1.3_DYNAMIC_APP_WORKSPACE_PRD.md`](../../docs/V1.3_DYNAMIC_APP_WORKSPACE_PRD.md)
- GitHub publication: Blocked on 2026-07-17 because the connected integration
  cannot create issues in `sunyych/SmartKeys` (`403 Resource not accessible by
  integration`).

## Objective

Implement the V1.3 Dynamic App Workspace PRD without regressing the V1.2
compatibility guarantees defined by that document.

## Definition of ready

- Product behavior, implementation decisions, protocol boundary, migration,
  testing decisions, acceptance criteria, and exclusions are specified in the
  linked PRD.
- The PRD identifies the deep modules and host/device verification required for
  implementation.
- No unresolved product decision is required before the first delivery slice:
  protocol and schema migration.

## Delivery order

1. Shared protocol v3 and manifest schema v2 migration.
2. Running App Monitor and Workspace Registry.
3. Desktop Applications and Connection management.
4. Paired WebSocket sessions and icon assets.
5. Dynamic mobile Workspace state.
6. Android Hybrid Mode.
7. iOS client.
8. macOS, Windows, Android, and iOS acceptance verification.
