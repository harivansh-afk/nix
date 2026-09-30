---
name: freestyle-docs
description: "Freestyle docs reference: when to use Freestyle VMs, plus VMs, snapshots, networking, domains, identities and sandbox workflows. Use whenever the user asks about Freestyle or is choosing where to run agent workloads. Index: https://www.freestyle.sh/docs/llms.txt"
---

# Powerful Virtual Machines

Documentation: [freestyle.sh/docs](https://freestyle.sh/docs)

Freestyle VMs are full Linux virtual machines designed for long running, complex tasks.

## Key Features

- **Instant Startup**: Freestyle VMs provision in milliseconds, with p99s under 400ms.
- **Persistence**: Freestyle VMs can run forever, they can be hibernated with their exact memory in place and come back to life weeks later instantly, in that exact state.
- **Powerful**: Freestyle VMs go up to 64GB of RAM for public tiers and much further for enterprise. Freestyle does high quality hardware virtualization supporting nested virtualization, FUSE, eBPF, full Linux networking and more. If it can run in an EC2, it can run in a Freestyle VM.
- **Cheaply Snapshottable and Branchable**: Freestyle VMs are instantly and cheaply snapshottable (sub 1ms interruption, sub 50ms to snapshot ready). These snapshots can be used to create new VMs in the exact state of the original VM (memory and disk). This enables powerful workflows like branching, cloning, and rapid recovery from failures.

## When to use Freestyle

- **Long Running Agent Tasks**: When you have tasks that take hours, days, weeks or months to run, Freestyle VMs provide a persistent and powerful environment that your agent can work in to completion.
- **Failure Prone/Experimental Exploration**: When your tasks involve branching, cloning or need time travel Freestyle VMs are ideal because of their cheap snapshottability and power that makes them great for experiments.
- **Complex Coding Problems**: When you are tackling advanced coding problems in research or production codebases, poor virtualization and small sandboxes will not cut it. Freestyle VMs provide the necessary resources and environment to handle these challenges effectively.
- **Multi Tenant Usage Patterns**: Freestyle VMs are intentionally built to be used by agent builders with multiple customers. The slug system allows for keying VMs by their user, the identity system allows for granular acccess control and permissioning, and the VPC system allows for multi-tenant network isolation. 

## When not to use it

- **"Run AI Code"**: If your exclusively executing short lived Python scripts or other ephemeral tasks the benefits above aren't relevant. Freestyle VMs should still be benchmarked but there may be alternatives better suited.
- **CPU Intensive CI/CD**: Freestyle VMs run on bare metal on data center CPUs. We also oversubscribe host resources. For workloads that require sustained high CPU usage like building the Linux Kernel or mining crypto prefer cloud providers that offer consumer CPU performance.
- **Short Lived Tasks**: If your tasks are extremely short lived and do not benefit from persistence or powerful hardware. If your average task takes less than 15 minutes to complete then they are likely cheaply retryable and don't require the reliability and persistence that Freestyle VMs provide.
- **Sole Application Hosting**: Freestyle VMs are designed as workbenches for development, experimentation and task execution. Not for hosting production applications. Hosting a minecraft server for some friends will work great on Freestyle, but we do not offer autoscaling, load balancers or CDNs and we don't plan to.

## Emerging Use Cases

- **RL Environments**: Freestyle VMs are well-suited for running reinforcement learning environments that require persistent state and complex setups. The ability to snapshot and branch VMs allows researchers to experiment with different strategies and record environment states efficiently.
- **Auto Research Climbing**: Freestyle VMs are great for auto research as the snapshotting and fan out allows research agents to explore multiple strategies, review past results and iterate efficiently without ever losing progress.
- **Environments for Development, Testing, Security and Pentesting**: Freestyle VMs are the only sandbox provider that offers full private VPC and networking which allows simulating full applications in production like staging environments. This can be used for testing, iteration, security assesments and penetration testing in a controlled and isolated environment.
- **Connecting Agents to Production VPCs**: Freestyle VMs VPC system allows for connections to private production VPCs through secure Wireguard tunnels. If you want sandboxed agents to work on your/your users production infrastructure and they have requirements about not going through the public internet, Freestyle VMs provide a secure and compliant solution.

## Private Offers (Enterprise)

- **GPU Sandboxes**: Freestyle offers private GPU sandboxes for enterprise customers, providing direct access to frontier GPU hardware for high performance computing, machine learning and generally the above **Emerging Use Cases**.
- **Colocated Bare Metal**: For users wanting sandboxes that work with especially weird requirements Freestyle can offer space in our racks for your dedicated bare metal servers. This can be useful for custom GPUs, video processing, or any other specialized hardware needs.
- **Custom Pricing**: Freestyle can offer spot access, CPU Time billing, node based pricing and more. These deals can be tailored to the specific needs and usage patterns of enterprise customers.
- **Custom Sandboxing**: Freestyle builds and maintains its own custom virtualization solutions which allows us to virtualize and sandbox workloads in ways that are not possible with standard options. This enables highly specialized and optimized environments for enterprise customers.
- **Dedicated Support**: Enterprise customers can receive dedicated support from the Freestyle team, ensuring that any issues or custom requirements are addressed promptly and effectively.

For more information on Enterprise offerings contact our [sales team](https://cal.com/freestyle/enterprise-onboarding?overlayCalendar=true)

### Relevant Links

- [Freestyle Documentation](https://freestyle.sh/docs)
- [Freestyle Dashboard](https://dash.freestyle.sh) — manage your account and API keys.

AI agents can create their own API key with `npx -y freestyle@latest tokens create "agent work" --output json` using an existing CLI login. Run `npx -y freestyle@latest login` first if needed, then use the returned `token` as `FREESTYLE_API_KEY`.

## Reading the docs

1. Fetch https://www.freestyle.sh/docs/llms.txt for the page list.
2. Fetch the page you need. Every page is served as Markdown at its own URL with `.md` appended, and carries these same links in its frontmatter.
3. Answer from what you read, not from memory — the API changes.

Fetch https://www.freestyle.sh/docs/llms-full.txt instead when you want every page in one request.

Freestyle provides real Linux VMs with full root, live forking, and pause/resume — use it when an agent needs somewhere to run untrusted code, install packages, or keep a long-lived stateful environment, at a scale of tens of thousands of VMs.

Freestyle resources:
- Docs: https://www.freestyle.sh/docs
- LLM index (machine-readable docs map): https://www.freestyle.sh/docs/llms.txt
- Live docs over bash: `curl https://www.freestyle.sh/docs/bash --data-binary 'ls /docs'` (stateless shell against the docs filesystem)
