# Scientific prompt

[system.txt](system.txt) is the only scientific prompt. Its words and punctuation
are preserved from Section 2.1 of the approved specification, with PDF line
wrapping and split-word artifacts normalized. [system.provenance.json](system.provenance.json)
records the source identity and approved prompt SHA-256. Tests prevent accidental edits.

The PydanticAI agent supplies this text once through `instructions=`. There is no
separate custom developer instruction block, reference brief or retrieval tool.
The user message supplies only measurements, exposed/unexposed sample sizes,
FWER/FDR and the numeric family level. Tool schemas supply the technical contract.

Export the complete model-visible input without credentials or provider requests:

```sh
poetry run python -m agents.document_preview --output deliverables/model-input.md
```

Older prompts are available in Git history, not in the current execution tree.
