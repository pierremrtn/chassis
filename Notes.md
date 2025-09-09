Pour maintenabilité et post-release bug finding:

Inclure un système de trace comprehensive ex:
command: [CommandName] from [ViewModel] got an error
    - params
    - error
-> uses code gen for auto logging utils generation ?
-> introduce mediator hooks for loggings utils

---

View model Auto dispose: trop simpliste.
- AJouter un system de disposable qui peuvent etre ajouté et disposé independent du lifecyle du view model
-> introduire une DisposableContainer ?