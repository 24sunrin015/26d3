# Wave 2: Runtime capacity

- Source steady state is two active nodes plus one stopped warm-pool EC2 inventory member; peak active nodes can be three.
- Live state confirms exactly two Ready nodes: one apps and one stress.
- Both nodes expose 1930m allocatable CPU.
- Apps node already requests 1474m; only 456m remains, below either 512m user/product replica request. Current user/product HPAs cannot scale even one workload under present controller placement, and no compatible apps node growth path exists.
- Stress node requests 1650m, so an additional 1500m pod necessarily becomes Pending and can activate the discovered stress ASG.
- Warm-pool promotion latency, downscale, and grader counting remain unverified without a controlled load cycle and official grader.

## EXPAND
- Closed by live snapshot: actual allocatable, requests, placement, HPA metrics, healthy targets.
- Open mutating/performance test: controlled stress 1→2→1 cycle.
