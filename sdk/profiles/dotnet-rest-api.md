Profile: **.NET / ASP.NET Core REST API**, laid out as one folder per module
under a commands or controllers root.

The script replaced the `{{...}}` placeholders below with this repository's real
paths before you saw this text.

## What a subject is

A **subject** is a module: one folder directly under `{{MODULE_ROOT}}`.

`{{MODULE_ROOT}}/Get/` is the module `Get`. A file belongs to module `X` when
its path starts with `{{MODULE_ROOT}}/X/`. A DTO or enum outside that folder
belongs to module `X` when module `X` uses it.

Each module folder holds a `<Name>Controller.cs` plus the DTOs it uses —
`<Name>Request.cs`, `<Name>Response.cs`, and any nested model.

## Routes

Controllers in this kind of repository usually derive from a shared base class
that carries `[ApiController]` and a `[Route(...)]` built from a constant in an
external NuGet package. **You cannot read that constant.** Do not guess the
route from it.

Verification rule — the real route is visible in the integration tests under
`{{TESTS_ROOT}}`. They call the endpoint by its literal URL, for example
`"{{ROUTE_PREFIX}}/cancelAndRefund"`. That is your source of truth for the path
and for its exact casing.

When no integration test covers the module, derive the route as
`{{ROUTE_PREFIX}}/<controller name without the "Controller" suffix, lowercased>`
and say in the document that the route is derived, not confirmed.

## Where to read

- Module source — `{{MODULE_ROOT}}/<Module>/`
- Integration tests — `{{TESTS_ROOT}}`
- Shared types and enums — `{{EXTRA_CONTEXT}}`
- Existing documents — `{{DOCS_DIR}}`

## Document naming

One file per module, kebab-case, under `{{DOCS_DIR}}`:

- `Get` → `{{DOCS_DIR}}/get.md`
- `BulkCreate` → `{{DOCS_DIR}}/bulk-create.md`
- `CancelAndRefund` → `{{DOCS_DIR}}/cancel-and-refund.md`

The folder may not exist yet. That is fine — create the file.

## Document skeleton

Use exactly this shape, so later runs produce small, readable diffs.

```markdown
# <Module>

> Autodoc. Last updated from <label from the `## This run` block> on <date>.

## POST {{ROUTE_PREFIX}}/<route>

<One short paragraph: what the endpoint does, in plain words.>

### Request — `<RequestClassName>`

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `UserProductId` | string | yes | ... |

### Response — `<ResponseClassName>`

| Field | Type | Nullable | Description |
| --- | --- | --- | --- |
| `Result` | `ResultInfo` | yes | ... |

<Repeat a "#### `<NestedClassName>`" table for each nested model.>

### Behavior

- Short bullets describing what the handler does, in order.
- Name the branch conditions that change the response.

### Errors

- Each failure the handler can produce, and what triggers it.
- Write "None found in the source" if the handler has no explicit failure path.

### Source

- `{{MODULE_ROOT}}/<Module>/<Name>Controller.cs`
- `{{TESTS_ROOT}}/<Module>/<Name>Tests.cs`
```

## Content rules

- `Required` is `yes` when the property has `[Required]` or the `required`
  keyword, otherwise `no`.
- `Nullable` is `yes` when the type ends with `?`.
- For an enum field, list its values inline in the Description, for example
  `VerificationStatus: Pending, Verified, Failed`. Read the enum file to get
  them — do not guess.
- One module may hold several endpoints. Repeat the `## POST ...` block for each
  controller action.

## JSON output for this profile

- `subject` — the module folder name, for example `Get`.
- `items` — one entry per documented endpoint:
  `{"kind": "endpoint", "name": "POST {{ROUTE_PREFIX}}/get", "change": "added"}`
