# Project Structure

This document describes the directory layout of the repository.

## Directories

| Directory | Purpose |
|-----------|---------|
| `app/` | Application source code files |
| `docs/` | User and developer documentation |
| `infrastructure-layered/` | Layered EKS infrastructure (base, networking, middleware, application) |
| `modules/` | Terraform modules (collections, primitives) |
| `test-harness/` | Optional isolated AWS prerequisites for testing |

## Key Entry Points

- **Deployment**: [infrastructure-layered/deploy.sh](../../infrastructure-layered/deploy.sh)
- **Documentation hub**: [docs/README.md](../README.md)
- **Operations guide**: [OPERATIONS.md](./OPERATIONS.md)
