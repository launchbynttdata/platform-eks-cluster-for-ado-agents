# Project Structure

This document describes the directory layout of the repository.

## Directories

| Directory | Purpose |
|-----------|---------|
| `app/` | Application source code files |
| `docs/` | User and developer documentation |
| `infrastructure-layered/` | Layered EKS infrastructure (base, middleware, application) |
| `modules/` | Terraform modules (collections, primitives) |
| `pipelines/` | Pipeline definition files |
| `tests/` | Test source code files |

## Key Entry Points

- **Deployment**: [infrastructure-layered/deploy.sh](../infrastructure-layered/deploy.sh)
- **Main documentation**: [infrastructure-layered/README.md](../infrastructure-layered/README.md)
- **Operations guide**: [OPERATIONS.md](./OPERATIONS.md)
