# RAG Stack Installation Guide (Host: hierophant)

This document provides instructions for executing the RAG stack installation using the master orchestration script. All commands are intended to be run from the local environment to remotely trigger execution on the **hierophant** host.

## Quick Start (Fresh Install)

To perform a complete, from-scratch installation of the basic infrastructure, build pipeline, and RAG services:

```bash
ssh -i ~/.ssh/id_hierophant_access -o BatchMode=yes -o StrictHostKeyChecking=no junie@hierophant \
"cd /mnt/hegemon-share/share/code/complete-build && \
FRESH_INSTALL=true VERSION=2.4.2 ./setup-complete.sh"
```

---

## Configuration Flags

The `setup-complete.sh` script supports several environment variables to control its behavior:

| Flag | Default | Description |
| :--- | :--- | :--- |
| `FRESH_INSTALL` | `false` | If `true`, resets all installation journals and forces steps to re-run. |
| `VERSION` | `1.0.0` | The version tag to use for building and deploying RAG service images. |
| `FORCE_REINIT` | `false` | If `true`, wipes and re-initializes Pulsar BookKeeper and other stateful components where supported. |
| `REPO_DIR` | (auto) | Overrides the path to the RAG stack directory. |

---

## Resuming a Failed Install

The installation process is **resumable**. If a step fails, you can investigate the logs on `hierophant`, fix the issue, and then run the command **without** `FRESH_INSTALL=true` to pick up exactly where it left off:

```bash
ssh -i ~/.ssh/id_hierophant_access -o BatchMode=yes -o StrictHostKeyChecking=no junie@hierophant \
"cd /mnt/hegemon-share/share/code/complete-build && \
VERSION=2.4.2 ./setup-complete.sh"
```

---

## Installation Steps (Summary)

The master script orchestrates the following major steps:
1. **Basic Infrastructure**: Bootstraps Rook-Ceph and Traefik.
2. **APM Stack**: Deploys LGTM (Loki, Grafana, Tempo, Mimir) and Grafana Alloy.
3. **NVIDIA stack**: Configures GPU support for inference nodes.
4. **Local Registry**: Sets up the internal container registry.
5. **Build Pipeline**: Configures the Kaniko + S3 cluster-native build system.
6. **RAG Images**: Builds all Go and Python services (v2.4.2) and pushes them to the registry.
7. **RAG Stack**: Deploys all services (LLM Gateway, Worker, Adapters, etc.) to the `rag-system` namespace.

---

## Troubleshooting

- **Logs**: Detailed logs for each service build are stored in `/mnt/hegemon-share/share/code/_KUBERNETES_BUILD/ai-changes/build-output/` on `hierophant`.
- **Journal**: Installation progress is tracked per-user under `~/.complete-build/journal/` on `hierophant`. Override with `INSTALL_JOURNAL_DIR` if needed.
- **Temporary Files**: Scripts use a private, user-specific temporary directory at `~/.complete-build/tmp/` on `hierophant`. Override with `INSTALL_TMP_DIR` if needed.
- **Kubernetes**: Use `/home/k8s/kube/kubectl` with `/home/k8s/kube/config/kubeconfig` on `hierophant` for cluster status.
