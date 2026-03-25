# File Integrity Monitoring in Containerised Environments

## The Ephemeral Pod Problem

Traditional FIM assumes long-lived hosts with persistent filesystems. Containers
fundamentally break this assumption:

| Traditional Host FIM | Container Reality |
|---|---|
| Baseline a filesystem, detect drift over time | Pod lifespan is minutes to hours — the filesystem is destroyed on termination |
| Monitor `/etc/passwd`, `/usr/bin`, config files | Container images are **immutable layers**; the running filesystem is an ephemeral overlay |
| Attribute changes to users via `auid` | Containers typically run as a single UID; `auid` attribution is meaningless inside a pod |
| auditd watches specific paths | Thousands of pods share the same kernel — auditd sees **all** of them, creating a firehose of noise |

### Does Ephemerality Collapse the Burden of Responsibility?

**No — it shifts it.** The responsibility doesn't disappear; it moves from runtime drift detection
to **supply chain integrity** and **runtime anomaly detection**:

1. **Image integrity replaces file integrity.** If the image is signed and verified at admission
   (e.g., via Sigstore/cosign + admission controllers like Kyverno or OPA Gatekeeper), then you
   know the starting state is trusted. Traditional FIM's "baseline" becomes the **image manifest**.

2. **Any runtime file modification is suspicious by default.** In an immutable infrastructure model,
   a container should *never* modify its own binaries or config files. Therefore, any write to the
   container's root filesystem is either a bug or a compromise — this is a much stronger signal
   than traditional FIM's "did the hash change?"

3. **Persistent volumes remain a FIM target.** Data volumes (`PersistentVolumeClaims`) survive pod
   restarts and contain stateful data (databases, uploads, configs). These still need traditional
   integrity monitoring.

4. **The control plane becomes the new attack surface.** Kubernetes API server, etcd, kubelet
   configs, RBAC policies, admission webhooks — these are the "critical system files" of a
   containerised environment. FIM for Kubernetes means monitoring these, not `/etc/passwd` inside
   a pod.

### The Paradigm Shift: From File Hashes to Behavioural Integrity

In containers, the question changes from:

> "Has this file changed since baseline?" (hash-based FIM)

To:

> "Is this container doing something its image was never built to do?" (behavioural integrity)

This is a fundamentally different — and arguably stronger — security model.

---

## How Container-Native FIM Actually Works

### Approach 1: Image Signing + Admission Control (Preventive)

- **Mechanism:** Sign container images at build time (cosign/Notary). Admission controllers
  reject unsigned or tampered images at deploy time.
- **What it replaces:** Baseline hash comparison. The "baseline" is the signed image digest.
- **Limitation:** Says nothing about runtime behaviour. A signed image with a vulnerability is
  still signed.
- **Tools:** Sigstore/cosign, Notary v2, Kyverno, OPA Gatekeeper, Connaisseur

### Approach 2: Read-Only Root Filesystem + Runtime Drift Detection

- **Mechanism:** Deploy containers with `readOnlyRootFilesystem: true` in the pod security
  context. Any write attempt to the root FS fails immediately.
- **What it replaces:** FIM alerting on file changes — changes are **prevented**, not just detected.
- **Limitation:** Many applications need writable `/tmp` or log directories. These are mounted
  as `emptyDir` volumes, which still need monitoring.
- **Tools:** Kubernetes SecurityContext, Pod Security Standards (Restricted profile)

### Approach 3: eBPF-Based Runtime Monitoring (Detective)

- **Mechanism:** eBPF programs attached to kernel tracepoints intercept syscalls (open, write,
  exec, connect) from within container namespaces. Events are enriched with container/pod metadata
  from the Kubernetes API.
- **What it replaces:** auditd. eBPF provides the same kernel-level visibility but with
  **container-aware context** (pod name, namespace, image, labels) that auditd lacks.
- **Key advantage:** Can enforce policy in-kernel (e.g., Tetragon can kill a process mid-syscall).
- **Tools:** Falco, Tetragon (Cilium), Tracee (Aqua Security), KubeArmor, Datadog Workload Protection

### Approach 4: Sidecar-Based FIM

- **Mechanism:** A FIM agent runs as a sidecar container in the same pod, sharing volumes with the
  application container. It watches for file changes using inotify/fanotify.
- **What it replaces:** Host-based FIM agents.
- **Limitation:** Adds resource overhead per pod. Cannot see the application container's root FS
  unless volumes are shared.
- **Tools:** [hammingweight/fim_sidecar](https://github.com/hammingweight/fim_sidecar),
  Wazuh agent sidecar, Tripwire Enterprise sidecar mode

### Approach 5: DaemonSet-Based Node Monitoring

- **Mechanism:** A privileged DaemonSet runs on every node, monitors the node filesystem
  (including container overlay filesystems in `/var/lib/containerd/`), and correlates events
  with pod metadata.
- **What it replaces:** Traditional host-based auditd/AIDE installations.
- **Tools:** Falco, Sysdig Secure, NeuVector

---

## The Novel Research Space

There is genuine novelty in this area. The core unsolved problems are:

### 1. Noise Reduction at Scale
Traditional FIM generates millions of events per day on a single host. In a cluster with
thousands of pods, this becomes billions. The IBM Research team demonstrated that **99.999% of
syscall events** in a production Kubernetes cluster are benign noise. Filtering this without
missing real threats is an active research problem.

### 2. Autonomous Allowlist Generation
Manually defining what a container "should" do is infeasible at scale. Research is exploring
automated profiling during CI/CD (learning phase) to generate per-image behavioural baselines
that are enforced at runtime — effectively auto-generating FIM policy from build artifacts.

### 3. Supply Chain Integrity as FIM
The SLSA (Supply chain Levels for Software Artifacts) framework, Sigstore ecosystem, and
in-toto attestation framework represent a new form of integrity monitoring that spans from
source code to running container. This is FIM extended across the entire software lifecycle,
not just the deployed filesystem.

### 4. eBPF as the Next-Generation FIM Engine
eBPF is displacing auditd for container monitoring because it can:
- Filter events in-kernel (reducing userspace overhead by orders of magnitude)
- Enrich events with container metadata at capture time
- Enforce policy synchronously (kill/deny at syscall boundary)
- Operate without modifying the monitored workload

---

## Key Research Papers

### Primary Papers

1. **"Highly-Scalable Container Integrity Monitoring for Large-Scale Kubernetes Cluster"**
   - **Authors:** Yuji Watanabe, Tsutomu Nakagawa, et al. (IBM Research, Tokyo)
   - **Venue:** IEEE International Conference on Big Data (Big Data 2020)
   - **Key contribution:** Novel filtering algorithm that reduces 99.999% of syscall noise
     by autonomously acquiring knowledge from the Kubernetes control plane — no predefined
     allowlists required.
   - **Link:** [IEEE Xplore](https://ieeexplore.ieee.org/document/9377815/)
   - **Link:** [IBM Research](https://research.ibm.com/publications/highly-scalable-container-integrity-monitoring-for-large-scale-kubernetes-cluster)

2. **"Real-time Container Integrity Monitoring for Large-Scale Kubernetes Cluster"**
   - **Authors:** Yuji Watanabe, Tsutomu Nakagawa, et al. (IBM Research, Tokyo)
   - **Venue:** Journal of Information Processing (JIP), Vol. 29, 2021
   - **Key contribution:** Extended version of the Big Data 2020 paper. Demonstrates real-time
     monitoring without predefined allowlist configurations, validated on production IBM Cloud
     Kubernetes clusters.
   - **Link:** [Full PDF (open access)](https://www.jstage.jst.go.jp/article/ipsjjip/29/0/29_505/_pdf)
   - **Link:** [Journal Page](https://www.jstage.jst.go.jp/article/ipsjjip/29/0/29_505/_article)

### eBPF-Focused Papers

3. **"Runtime Security Monitoring with eBPF"**
   - **Authors:** Guillaume Fournier, Sylvain Afchain, Sylvain Baubeau
   - **Venue:** SSTIC 2021 (Symposium sur la Sécurité des Technologies de l'Information et des Communications)
   - **Key contribution:** Demonstrates how eBPF enables a new generation of runtime security
     tools with better performance, context, and signal-to-noise ratio than traditional approaches
     including auditd.
   - **Link:** [SSTIC Paper (PDF)](https://www.sstic.org/media/SSTIC2021/SSTIC-actes/runtime_security_with_ebpf/SSTIC2021-Article-runtime_security_with_ebpf-fournier_afchain_baubeau.pdf)

4. **"eBPF-PATROL: Protective Agent for Threat Recognition and Overreach Limitation"**
   - **Authors:** (Multiple contributors)
   - **Venue:** arXiv preprint, 2025
   - **Key contribution:** Lightweight eBPF-based runtime security agent for containerised and
     virtualised environments with real-time threat detection and adaptive policy enforcement.
   - **Link:** [arXiv](https://arxiv.org/html/2511.18155v1)

5. **"Comparative Analysis of eBPF-Based Runtime Security Monitoring"**
   - **Venue:** SciTePress, 2025
   - **Key contribution:** Evaluates Falco, Tetragon, and Tracee against OWASP Kubernetes Top 10
     attack scenarios (container escape, DoS, cryptomining).
   - **Link:** [Paper (PDF)](https://www.scitepress.org/Papers/2025/142727/142727.pdf)

6. **"Hybrid Runtime Detection of Malicious Containers Using eBPF"**
   - **Venue:** Computers, Materials & Continua (CMC), Vol. 86, No. 3
   - **Key contribution:** Hybrid detection framework leveraging eBPF to simultaneously collect
     flow-based network metadata and host-based syscall traces for container anomaly detection.
   - **Link:** [TechScience](https://www.techscience.com/cmc/v86n3/65510)

7. **"Enhancing DFIR in Orchestration Environments: Real-time Forensic Framework with eBPF"**
   - **Venue:** ScienceDirect, 2025
   - **Key contribution:** eBPF-based forensic framework for digital forensics and incident
     response in orchestrated container environments.
   - **Link:** [ScienceDirect](https://www.sciencedirect.com/science/article/pii/S2666281725000629)

### Industry Engineering References

8. **"Scaling Real-time File Monitoring with eBPF: How We Filtered Billions of Kernel Events Per Minute"**
   - **Author:** Datadog Engineering
   - **Key contribution:** Production-scale eBPF FIM implementation filtering billions of kernel
     events per minute with minimal overhead.
   - **Link:** [Datadog Blog](https://www.datadoghq.com/blog/engineering/workload-protection-ebpf-fim/)

---

## Compliance Perspective: What Auditors Actually Expect

### PCI-DSS v4.0

**Requirement 11.5.2** mandates a "change-detection mechanism" to alert on unauthorised
modification of critical files. The standard is technology-agnostic — it does not say "install
Tripwire on every host." In a containerised environment, the following controls satisfy the
intent:

| PCI-DSS Requirement | Container-Native Control | Evidence |
|---|---|---|
| 11.5.2 — Detect unauthorised changes to critical files | Image signing + admission control (cosign + Kyverno) | Admission controller logs showing rejected unsigned/tampered images |
| 11.5.2 — Alert personnel | eBPF runtime monitoring (Falco/Tetragon) alerting on unexpected file writes | SIEM alerts from Falco rules firing on write events in immutable containers |
| 11.5.2 — Perform comparisons at least weekly | Image digest verification on every pod schedule (continuous, not weekly) | Kubernetes audit logs showing image verification on admission |
| 10.2 — Audit logging of access to system components | Kubernetes audit logging + eBPF syscall capture | Centralised audit logs with pod-level attribution |
| 10.3.4 — Log integrity protection | Immutable log forwarding (Fluent Bit → SIEM) | Logs never touch writable pod storage |

**Key argument for auditors:** Containers provide **stronger** integrity guarantees than
traditional FIM because:
- The baseline is cryptographically signed (image digest), not just a hash database
- Verification happens on **every deployment**, not on a weekly scan schedule
- Any runtime deviation from the signed image is blocked or alerted in real-time
- The immutable infrastructure model means drift is prevented, not just detected

### ISO 27001:2022

**Control A.8.19 (Installation of software on operational systems)** maps directly to admission
control — only signed, approved images can be deployed. The Kubernetes admission controller log
is the evidence artifact.

**Control A.12.4.1 (Event logging)** is satisfied by eBPF-based runtime monitoring + Kubernetes
audit logs, which together provide richer attribution than host-level auditd.

### SOC 2 Type II

SOC 2's "Change Management" criteria (CC8.1) requires evidence that changes to infrastructure
are authorised and monitored. In a GitOps model:
- All container image changes flow through CI/CD (authorised via PR review)
- Image signing proves the artifact matches the approved source
- Admission control enforces that only signed artifacts deploy
- Runtime monitoring catches any out-of-band changes

This is a **tighter control loop** than traditional change management + FIM.

### Compliance Gap: What Containers Don't Solve

| Gap | Why It Matters | Mitigation |
|---|---|---|
| Node-level FIM still needed | Kubernetes nodes are still Linux hosts — kubelet, containerd, etcd need traditional FIM | Keep auditd/AIDE on nodes (this project's current scope) |
| PersistentVolume integrity | Stateful data survives pod restarts — traditional hash-based FIM still applies | Mount PVs read-only where possible; AIDE for writable PVs |
| Auditor education | Many assessors still expect to see "Tripwire" or equivalent — need to demonstrate equivalence | Prepare a control mapping document (like this one) |
| Multi-tenancy attribution | Shared clusters make it harder to attribute changes to specific teams | Namespace-level RBAC + eBPF context enrichment with namespace/service account |

---

## Engineering Perspective: Practical Implementation Challenges

### Challenge 1: The Monitoring Paradox

To monitor containers, you need a privileged monitoring agent. But privileged agents are
themselves an attack surface. Solutions:

- **Falco:** Runs as a kernel module or eBPF program — DaemonSet needs `privileged: true`
- **Tetragon:** Runs as eBPF — needs `CAP_BPF`, `CAP_SYS_ADMIN` on the DaemonSet
- **Trade-off:** Accept a small, audited privileged surface (the monitor) to gain visibility
  over the entire cluster

### Challenge 2: Performance at Scale

Real numbers from the research:
- A single Kubernetes node can generate **100,000+ syscall events per second**
- A 500-node cluster produces **billions of events per minute**
- Datadog's production eBPF FIM implementation filters events in-kernel, reducing userspace
  processing by **95%+**
- IBM's research showed that control-plane-aware filtering eliminates **99.999%** of noise

**Engineering implication:** In-kernel filtering (eBPF) is not optional at scale — userspace
processing (auditd model) cannot keep up with container event volumes.

### Challenge 3: Ephemeral Forensics

When a compromised pod is killed (either by an attacker covering tracks or by Kubernetes
autoscaling), the filesystem evidence is gone. Engineering solutions:

- **Pre-mortem capture:** eBPF tools can snapshot container state before termination
- **Immutable log streaming:** Stream all events to external storage in real-time (never buffer
  in the pod)
- **Container image forensics:** If the running image diverges from the signed digest, capture
  the modified layers before pod termination
- **Pod termination hooks:** `preStop` hooks can trigger evidence collection

### Challenge 4: CI/CD Integration

FIM in containers must start at build time, not deploy time:

```
Source Code → Build → Sign Image → Push to Registry → Admission Control → Runtime Monitor
     ↑            ↑         ↑              ↑                  ↑                  ↑
  git signing  SBOM gen   cosign      signature verify    policy enforce    eBPF detect
  (integrity)  (supply    (image       (registry           (Kyverno/OPA)    (Falco/
               chain)     integrity)    integrity)                          Tetragon)
```

Each stage is a form of integrity monitoring. Traditional FIM only covers the last step.

### Challenge 5: Multi-Cluster and Hybrid Environments

Most enterprises don't run pure Kubernetes. They have:
- Legacy VMs running auditd (this project)
- Kubernetes clusters needing eBPF-based monitoring
- Serverless functions (Lambda/Cloud Run) with no filesystem access at all
- Edge devices with constrained resources

**Engineering reality:** You need a **unified policy framework** that expresses integrity
requirements once and enforces them differently per platform. This is an unsolved problem
and an active area of research.

### Challenge 6: Alert Fatigue and Tuning

The IBM research paper's key finding is that the hardest engineering problem isn't detection —
it's **noise reduction**. Their approach:
1. Query the Kubernetes API for expected pod behaviour (image manifest, command, args)
2. Automatically generate allowlists from the container image's declared entrypoint and installed packages
3. Flag only syscalls that deviate from the expected profile
4. Reduce false positives by **99.999%** without manual rule tuning

This is the most promising engineering direction: **using the container's own metadata as the
FIM baseline**, rather than manually defining what "normal" looks like.

---

## Implications for This Project (auditd-based FIM)

This project's auditd-based FIM is designed for **traditional host environments**. The
`prod.rules` already exclude container runtimes (`docker`, `containerd`) from monitoring to
reduce noise — which is the correct approach for host-level FIM.

However, if the fleet moves toward containerised workloads, the following gaps emerge:

| Current Capability | Container Gap |
|---|---|
| auditd syscall monitoring | No container-aware context (pod name, namespace, image) |
| `auid` attribution | Meaningless inside containers (single UID, no login session) |
| File path watches (`/etc/passwd`, `/usr/bin`) | These paths exist per-container in overlay FS — auditd sees the host paths in `/var/lib/containerd/` |
| AIDE hash baselines | Container images already provide signed digests — AIDE is redundant for immutable containers |
| Tanium deployment | Tanium agents run on nodes, not inside pods — sidecar or DaemonSet model needed |

### Recommended Evaluation Path

If containerisation is on the roadmap:

1. **Phase 1:** Evaluate Falco or Tetragon as the eBPF-based successor to auditd for container workloads
2. **Phase 2:** Implement image signing (cosign) + admission control (Kyverno) for supply chain integrity
3. **Phase 3:** Enforce `readOnlyRootFilesystem` across all workloads via Pod Security Standards
4. **Phase 4:** Integrate container runtime events into existing SIEM pipeline alongside auditd host events
