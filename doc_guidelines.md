C'est parfait. Le style de la documentation Flutter est **pédagogique, bienveillant ("gentle introduction") et structurel**. Elle ne vend pas le produit, elle explique les **principes** et comment le framework s'y conforme.

Voici le fichier `DOC_GUIDELINES.md` rédigé pour forcer le LLM à adopter ce ton précis (autoritaire mais accessible, axé sur les principes d'ingénierie logicielle).

---

### Fichier : `DOC_GUIDELINES.md`

```markdown
# Documentation Guidelines for Chassis

## 1. Voice and Tone
The documentation should mimic the official **Flutter Documentation style**.

* **Educational & "Gentle":** Treat the reader as an intelligent peer who wants to learn best practices. Use phrases like *"In the simplest terms"*, *"This promotes modularity"*, or *"Ideally, your application should..."*.
* **Principle-First:** Do not just explain *how* to use a tool; explain the *architectural principle* behind it (e.g., Separation of Concerns, Unidirectional Data Flow).
* **Objective & Measured:**
    * ❌ **Avoid:** "Chassis is the best framework," "It works like magic," "Stop the pain of spaghetti code."
    * ✅ **Use:** "Chassis encourages a layered architecture," "Code generation automates the wiring," "This improves maintainability."
* **Authoritative but Flexible:** Acknowledge that architectural choices depend on complexity. Use the "90/10" concept as a flexibility feature, not a rigid rule.

## 2. Structure of Concepts
When introducing a new concept (e.g., `Command`, `Mediator`, `AsyncBuilder`), follow this pattern found in Flutter docs:

1.  **The Principle:** Define the software engineering concept (e.g., "Command Pattern", "Reactive UI").
2.  **The Context:** Explain how it fits into the Flutter ecosystem.
3.  **The Implementation:** Show how Chassis implements this principle.
4.  **The Benefit:** Conclude with *why* this matters (Testability, Extensibility, etc.).

**Example:**
> *Instead of "Use commands to update data," write:*
> "Unidirectional Data Flow helps decouple state from the UI. In Chassis, this is achieved through **Commands**. A Command expresses a clear intent to change state, flowing from the UI layer to the Logic layer."

## 3. Formatting Standards
* **Paragraphs:** Keep them short (2-4 sentences). Large blocks of text are hard to scan.
* **Lists:** Use bullet points for features, steps, or benefits.
* **Bold:** Use bold text **only** for new vocabulary or critical emphasis.
* **Code Snippets:**
    * Must be concise.
    * Must focus on the specific concept being explained.
    * Use standard Dart formatting.

## 4. Vocabulary & Terminology
Adopt a standard, engineering-focused vocabulary.

| Concept | ❌ Avoid (Marketing/Casual) | ✅ Preferred (Flutter/Engineering) |
| :--- | :--- | :--- |
| **Generator** | "Magic", "It just works", "Wizard" | "Automated wiring", "Code generation", "Compile-time safety" |
| **Architecture** | "The best way", "The only way" | "Recommended architecture", "Opinionated structure", "Design pattern" |
| **Simplicity** | "Easy", "Simple", "No-brainer" | "Straightforward", "Streamlined", "Low-friction" |
| **Async** | "Handling futures is hard" | "Asynchronous state modeling", "Reactive primitives" |

## 5. Specific Directives for Chassis

### On "Chassis Builder" (The Automation)
Do not present the builder as a "crutch" for lazy developers. Present it as a tool for **Consistency** and **Type Safety**.
* *Phrasing:* "The builder ensures that all handlers are correctly registered with the Mediator, eliminating runtime errors associated with manual wiring."

### On "Async<T>" (The State)
Frame this as **"UI is a function of state"**.
* *Phrasing:* "Chassis provides the `Async<T>` type to model the complete lifecycle of data interaction (Loading, Data, Error), ensuring your UI always reflects the current state of the operation."

### On "Manual vs. Generated"
Frame this as **"Extensibility"**.
* *Phrasing:* "While code generation handles standard CRUD operations efficiently, the architecture remains open. You can manually implement handlers when your application requires complex business logic or orchestration."

## 6. Review Checklist
Before outputting any section, ask:
1.  Does this sound like it belongs on `flutter.dev/docs`?
2.  Did I explain the *Why* before the *How*?
3.  Did I remove all "salesy" adjectives?
4.  Is the distinction between UI Layer, Logic Layer, and Data Layer clear?

```