# Layer dependencies

| Layer | Allowed dependencies |
| --- | --- |
| Presentation | Domain entities/protocols, Core, UI frameworks |
| Domain | Foundation, Core |
| Platform | Domain contracts, Core, Infra, provider packages |
| Infra | Foundation/system frameworks only |
| App | All layers for composition |

View models never create concrete repositories/clients or depend on AppConfig. Inject
focused settings protocols and services. New settings orchestration belongs in Platform;
UserDefaults execution stays in Infra. Domain never imports AppKit or provider packages.

Run `bash scripts/check-architecture.sh`; CI enforces these boundaries and rejects the
removed server/sample symbols. Unit tests target services and view models, never Views.
