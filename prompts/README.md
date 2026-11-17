# Which prompt is current?

The current scientific prompt is [document-20261111.txt](document-20261111.txt),
the unchanged Section 2.1 text from the approved specification. The familiar
[system.txt](system.txt) filename contains an identical copy. Tests check both
against the recorded SHA-256 digest to prevent drift.

The current agent loads the versioned file once through PydanticAI `instructions=`.
It receives no additional custom scientific system/developer block or reference
brief. Dimensions, criterion and family level arrive in the user message; tool
schemas describe the technical interface. See [the workflow guide](../docs/document-workflow.md).

| Protocol | Configuration | Scientific prompt | Additional instructions |
|:--|:--|:--|:--|
| Current, default | `config/document-pilot.yml` | `document-20261111.txt` (identical to `system.txt`) | Technical tool/output interfaces only |
| Legacy, explicit selection | `config/pilot.yml` | `legacy-system.txt` | `legacy-developer.txt` and the historical reference brief |

The legacy files preserve the previous prompt bytes. They support interpreting
and running the historical protocol; they are not inputs to the current sessions.
For exact resumption of a saved run, use its original source revision and config:
strict fingerprints intentionally detect any code, path or prompt-file changes.

Export the current model-visible input without credentials or API requests:

```sh
poetry run python -m agents.document_preview --output deliverables/current-model-input.md
```
