# build and run live demo

## Prerequisites

- Docker: https://docs.docker.com/engine/install/
- Kind: https://kind.sigs.k8s.io/
- kubectl: https://kubernetes.io/docs/tasks/tools/
- helm: https://helm.sh/docs/intro/install/
- Stern: https://github.com/stern/stern
- Kubectx & Kubens: https://github.com/ahmetb/kubectx

## Environment

- 3 nodes as control plane
- 3 nodes as workers

### Architecture Diagram

```mermaid
graph TB
    %% Kind Cluster
    subgraph kind["Kind Cluster: build-and-run"]
        %% Node groups
        subgraph control["Control Plane Nodes (3)"]
            cp1["Control Plane 1"]
            cp2["Control Plane 2"]
            cp3["Control Plane 3"]
            metrics["Metrics Server"]
        end
        
        subgraph workers["Worker Nodes (3)"]
            %% No node labels shown in this script version
            w1["Worker 1"]
            w2["Worker 2"]
            w3["Worker 3"]
        end

        %% Namespaces
        subgraph obs["Namespace: observability"]
            %% Monitoring components
            grafana["Grafana"]
            vmsingle["Victoria Metrics Single"]
            vmagent["VM Agent"]
            vmalert["VM Alert"]
            alertmanager["Alertmanager"]
            kube_state["kube-state-metrics"]
            
            %% Logging components
            loki["Loki"]
            promtail["Promtail"]
        end

        %% Customer namespaces from the script
        subgraph ns1["Namespace: ns-52327214"]
            tb1["Trouble-Box App"]
            svc1["Service"]
            pvc1["PVC"]
            pv1["PV"]
            cron1["Cleanup CronJob"]
        end

        subgraph ns2["Namespace: ns-48414609"]
            tb2["Trouble-Box App"]
            svc2["Service"]
            pvc2["PVC"]
            pv2["PV"]
            cron2["Cleanup CronJob"]
        end

        subgraph ns3["Namespace: ns-94714545"]
            tb3["Trouble-Box App"]
            svc3["Service"]
            pvc3["PVC"]
            pv3["PV"]
            cron3["Cleanup CronJob"]
        end

        %% Component connections
        grafana --> vmsingle
        grafana --> loki
        vmagent --> vmsingle
        vmagent --> tb1
        vmagent --> tb2
        vmagent --> tb3
        vmagent --> kube_state
        vmalert --> vmsingle
        vmalert --> alertmanager
        promtail --> loki
        
        %% Application connections
        tb1 --> pvc1
        pvc1 --> pv1
        cron1 --> pv1
        svc1 --> tb1
        
        tb2 --> pvc2
        pvc2 --> pv2
        cron2 --> pv2
        svc2 --> tb2
        
        tb3 --> pvc3
        pvc3 --> pv3
        cron3 --> pv3
        svc3 --> tb3
    end
    
    %% External access
    user["User/Admin"]
    user -->|port-forward 3000:80| grafana
    user -->|port-forward 8428:8428| vmsingle
    user -->|port-forward 8429:8429| vmagent
    user -->|port-forward 8880:8880| vmalert
    user -->|port-forward 9093:9093| alertmanager
```

### Observability stack

- Grafana
- Victoria Metrics
- Loki
- Promtail
- Alertmanager
- kubestate metrics

### Workloads

Troublebox app

### Setting up

```bash
./deploy.sh
```

### Access

Grafana

Get pass:
kubectl get secret --namespace observability grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo

kubectl port-forward -n observability svc/grafana 3000:80
url: http://localhost:3000

Victoria Metrics

kubectl port-forward -n observability svc/vmsingle-victoria-metrics-single-server 8428:8428
url: http://localhost:8428

Victoria Metrics vmagent

kubectl port-forward -n observability svc/vmagent 8429:8429
url: http://localhost:8429

Victoria Metrics vmalert
kubectl port-forward -n observability svc/vmalert-victoria-metrics-alert-server 8880:8880
url: http://localhost:8880

Alertmanager
kubectl port-forward -n observability svc/alertmanager 9093:9093
url: http://localhost:9093


