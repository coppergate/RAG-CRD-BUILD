# RAG Stack Diagrams

This directory contains the Mermaid source code for the RAG stack architecture and workflows. These files are provided in a standalone format to make them easier to edit and maintain.

## 1. Available Diagrams

- **[architecture.mmd](./architecture.mmd)**: The high-level component architecture and message interconnections (Iteration 9+).
- **[build-flow.mmd](./build-flow.mmd)**: The bootstrapping and in-cluster build pipeline stages.
- **[ui-layout.mmd](./ui-layout.mmd)**: The structural design of the RAG Explorer (Flutter) application and its relationship to the BFF.

## 2. How to Edit and View

### A. Mermaid Live Editor (Web)
1. Copy the contents of any `.mmd` file.
2. Go to [Mermaid.live](https://mermaid.live).
3. Paste the code into the "Code" panel.
4. Export the result as **SVG**, **PNG**, or **JSON**.

### B. VS Code / JetBrains IDEs
- Use a Mermaid extension (e.g., "Mermaid Editor" or "Markdown Mermaid") to get real-time previews directly in the editor.

### C. Draw.io / Diagrams.net
You can import these diagrams into Draw.io for manual visual editing:
1. Open [Diagrams.net](https://app.diagrams.net).
2. Go to **Arrange > Insert > Advanced > Mermaid...**.
3. Paste the Mermaid code and click **Insert**.
4. You can now move components around and style them manually.

### D. Obsidian
If you use Obsidian, you can simply reference these files or embed them using a code block:
```mermaid
[Paste content here]
```

## 3. Maintenance Policy

When updating the architecture in the Markdown documentation (e.g., `RAG Stack Architecture.md`), ensure the corresponding `.mmd` files in this directory are synchronized to maintain them as the "editable source of truth."
