# Truve K8s Resources

## App Node Fixed Pod 확인

`app-general` 노드에 붙어 있는 파드 중 `DaemonSet`을 제외하고 확인합니다.

```sh
./scripts/app-node-ops.sh list-app-nodes
./scripts/app-node-ops.sh list-fixed-pods
```

특정 문제 노드에 남아 있는 파드만 보려면 아래 명령을 사용합니다.

```sh
./scripts/app-node-ops.sh list-node-pods <node-name>
```

기존 app 노드에 taint가 비어 있으면 아래 명령으로 일괄 적용합니다.

```sh
./scripts/app-node-ops.sh taint-app-nodes
```

직접 명령으로 확인하려면 아래처럼 조회하면 됩니다.

```sh
for node in $(kubectl get nodes -l karpenter.sh/nodepool=app-general -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'); do
  kubectl get pods -A \
    --field-selector "spec.nodeName=${node}" \
    -o custom-columns='NODE:.spec.nodeName,NAMESPACE:.metadata.namespace,NAME:.metadata.name,OWNER_KIND:.metadata.ownerReferences[0].kind,OWNER_NAME:.metadata.ownerReferences[0].name,PHASE:.status.phase' \
    --no-headers
done | awk '$4 != "DaemonSet"'
```

app 노드에 배치되는 Deployment만 보고 싶으면 아래 명령을 사용합니다.

```sh
kubectl get deploy -A -o jsonpath='{range .items[?(@.spec.template.spec.nodeSelector.workload=="app")]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}'
```

## Night-Day Scheduler 동작

`chart/night-day-scheduler`는 이제 두 가지 대상을 같이 스케일합니다. CronJob 자체는 `system` 노드에서만 돌도록 고정했습니다.

- `targets.deployments`: replica 복원값을 명시적으로 관리할 서비스
- `targets.autoDiscoverAppDeployments`: `spec.template.spec.nodeSelector.workload=app` 인 Deployment를 자동 탐지할 대상

덕분에 서비스 파드 외에 app 노드에 고정적으로 올라가는 Deployment가 생겨도 nightly scale down 대상에서 빠지지 않습니다.

또한 `app-general` NodePool에는 `workload=app:NoSchedule` taint를 적용하고, 실제 서비스 Deployment들에만 같은 toleration을 추가했습니다. 그래서 `external-secrets`, `istiod`, `aws-load-balancer-controller`, `kube-state-metrics` 같은 비앱 파드가 app 노드로 들어와 Karpenter scale down을 막는 상황을 줄일 수 있습니다.

주의할 점은 NodePool template 변경이 기존 노드의 taint를 자동으로 바꾸지는 않는다는 것입니다. 이미 생성된 app 노드에는 수동으로 taint를 넣거나 drain 후 교체가 필요합니다.

```sh
kubectl taint node <app-node-name> workload=app:NoSchedule
```

또한 app 노드 수가 적을 때도 비어 있는 노드를 줄일 수 있도록 `app-general` NodePool의 disruption budget은 최소 1대로 설정했습니다.

## 장애 노드 복구

Terminating 파드 확인:

```sh
./scripts/app-node-ops.sh list-terminating
```

`auth-service`, `ticketing-service`의 stuck Terminating 파드 강제 삭제:

```sh
./scripts/app-node-ops.sh cleanup-terminating
```

특정 노드 drain:

```sh
./scripts/app-node-ops.sh drain-node <node-name>
```
