# Working in SYMPHONY

This project targets Jac 0.37.25. Before editing Jac files, use the compiler's versioned guides instead of relying on older Jac syntax:

- `jac guide jac-essentials`
- `jac guide jac-cl-components`
- `jac guide jac-cl-organization`
- `jac guide jac-sv-endpoints`
- `jac guide jac-by-llm` when implementing the Investigator

Run `jac check main.jac` after changing contracts, imports, components, or endpoints. Run the app with `jac run --dev main.jac`.

The contracts in `contracts.jac` and operation names in `operations.jac` are the integration boundary. Keep unfinished behavior explicit and never return fake successful scans or investigations.
