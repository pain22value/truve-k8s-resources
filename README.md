# Truve K8s Resources

Truve 프로젝트의 Kubernetes 인프라 관리 리포지토리입니다. ArgoCD를 통한 GitOps 방식으로 EKS 클러스터의 모든 리소스를 관리합니다.

## 목차

- [아키텍처 개요](#아키텍처-개요)
- [디렉토리 구조](#디렉토리-구조)
- [주요 컴포넌트](#주요-컴포넌트)
- [배포 프로세스](#배포-프로세스)
- [운영 가이드](#운영-가이드)
  - [App Node 관리](#app-node-관리)
  - [Night-Day Scheduler](#night-day-scheduler)
  - [장애 노드 복구](#장애-노드-복구)

## 아키텍처 개요

### GitOps with ArgoCD

이 리포지토리는 **App of Apps** 패턴을 사용하여 모든 쿠버네티스 리소스를 관리합니다:

1. **Root App** (`app/root-app.yaml`): 모든 ArgoCD Application을 관리하는 최상위 Application
2. **Service Apps**: 각 마이크로서비스별 Application (gateway, auth, ticketing, queue, payment, musical)
3. **Infrastructure Apps**: 공통 인프라 컴포넌트 (ArgoCD, Kafka, Karpenter, KEDA, Redis 등)
4. **Observability Apps**: 모니터링 스택 (Prometheus, Grafana, Loki, Tempo, Fluent Bit, OpenTelemetry)

### 자동화 워크플로우

- **ArgoCD Image Updater**: ECR의 최신 이미지를 감지하여 자동 배포
- **Night-Day Scheduler**: 비용 절감을 위한 야간 스케일 다운/아침 스케일 업
- **Karpenter**: 워크로드에 따른 노드 자동 프로비저닝 및 최적화
- **KEDA**: Kafka 큐 기반 파드 오토스케일링

## 디렉토리 구조

```
k8s-resources/
├── app/                          # ArgoCD Application 매니페스트
│   ├── root-app.yaml            # App of Apps 루트
│   ├── *-service.yaml           # 마이크로서비스 Applications
│   ├── argocd.yaml              # ArgoCD 자체 관리
│   ├── argocd-image-updater.yaml # 이미지 자동 업데이트
│   ├── kafka.yaml               # Kafka 클러스터
│   ├── karpenter.yaml           # 노드 오토스케일러
│   ├── keda.yaml                # KEDA 컨트롤러
│   ├── keda-scalers.yaml        # KEDA ScaledObject 정의
│   ├── redis.yaml               # Redis 클러스터
│   ├── night-day-scheduler.yaml # 비용 최적화 스케줄러
│   ├── circuit-breaker.yaml     # 서킷 브레이커 설정
│   ├── kubecost.yaml            # 비용 모니터링
│   ├── common.yaml              # 공통 리소스
│   ├── observability/           # 관측성 스택
│   └── ingress/                 # Ingress 리소스
├── chart/                        # Helm Chart 값 및 템플릿
│   ├── *-service/               # 서비스별 Helm values
│   ├── argocd/                  # ArgoCD 설정
│   ├── karpenter/               # NodePool, EC2NodeClass 설정
│   ├── kafka/                   # Kafka 설정
│   ├── redis/                   # Redis 설정
│   ├── keda-scalers/            # KEDA ScaledObject 정의
│   ├── night-day-scheduler/     # 스케줄러 설정
│   ├── kubecost/                # Kubecost 설정
│   ├── common/                  # 공통 리소스
│   ├── aws-ebs-csi-driver/      # EBS CSI 드라이버
│   ├── fluent-bit/              # 로그 수집
│   ├── monitoring/              # 모니터링 스택
│   └── observability/           # 관측성 스택 values
└── scripts/                      # 운영 스크립트
    └── app-node-ops.sh          # 노드 관리 유틸리티
```

## 주요 컴포넌트

### 마이크로서비스

| 서비스 | 네임스페이스 | 설명 |
|--------|-------------|------|
| Gateway | truve-gateway-service | API Gateway |
| Auth | truve-auth-service | 인증/인가 서비스 |
| Ticketing | truve-ticketing-service | 티켓 예매 서비스 |
| Queue | truve-queue-service | 대기열 관리 서비스 |
| Payment | truve-payment-service | 결제 서비스 |
| Musical | truve-musical-service | 뮤지컬 정보 서비스 |

### 인프라 컴포넌트

- **ArgoCD**: GitOps CD 플랫폼
- **ArgoCD Image Updater**: ECR 이미지 자동 업데이트
- **Kafka**: 이벤트 스트리밍 플랫폼
- **Redis**: 인메모리 데이터 스토어 및 캐시
- **Karpenter**: AWS 노드 자동 프로비저닝
  - `app-general` NodePool: 일반 애플리케이션용 (Spot, t3a.small/medium)
  - `app-stream` NodePool: 스트림 처리용 (비활성화됨)
- **KEDA**: Kafka, Redis ZSET 메트릭 기반 HPA
- **Kubecost**: Kubernetes 비용 모니터링

### 관측성 스택

- **Prometheus & Grafana**: 메트릭 수집 및 시각화
- **Loki**: 로그 집계
- **Tempo**: 분산 추적
- **Fluent Bit**: 로그 수집
- **OpenTelemetry Collector**: 텔레메트리 데이터 수집

## 배포 프로세스

### 초기 배포

```bash
# Root App 배포 (모든 리소스 자동 배포)
kubectl apply -f app/root-app.yaml
```

### 이미지 자동 업데이트

ArgoCD Image Updater가 ECR을 모니터링하여 새 커밋 해시 태그를 감지하면:

1. 해당 서비스의 `chart/*-service/values.yaml` 파일 업데이트
2. Git 커밋 생성
3. ArgoCD가 변경사항 감지 후 자동 배포

## 운영 가이드

### App Node 관리

#### App Node Fixed Pod 확인

`app-general` 노드에 붙어 있는 파드 중 `DaemonSet`을 제외하고 확인합니다.

```sh
./scripts/app-node-ops.sh list-app-nodes
./scripts/app-node-ops.sh list-fixed-pods
```

특정 문제 노드에 남아 있는 파드만 보려면 아래 명령을 사용합니다.

```sh
./scripts/app-node-ops.sh list-node-pods <node-name>
```

#### Taint 관리

`app-general` NodePool은 `workload=app:NoSchedule` taint를 사용하여 앱 파드만 스케줄링됩니다.

기존 app 노드에 taint가 비어 있으면 아래 명령으로 일괄 적용합니다.

```sh
./scripts/app-node-ops.sh taint-app-nodes
```

수동으로 특정 노드에 적용:

```sh
kubectl taint node <app-node-name> workload=app:NoSchedule
```

#### 배치 확인

app 노드에 배치되는 Deployment만 보고 싶으면 아래 명령을 사용합니다.

```sh
kubectl get deploy -A -o jsonpath='{range .items[?(@.spec.template.spec.nodeSelector.workload=="app")]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}'
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

### Night-Day Scheduler

비용 절감을 위해 야간(18시)에 서비스를 스케일 다운하고 아침(9시)에 다시 스케일 업합니다.

#### 동작 방식

`chart/night-day-scheduler`는 두 가지 방식으로 대상을 관리합니다:

1. **명시적 관리** (`targets.deployments`): 각 서비스별 dayReplicas 지정
2. **자동 탐지** (`targets.autoDiscoverAppDeployments`): `workload=app` nodeSelector를 가진 Deployment 자동 탐지

**스케줄**:
- Day (09:00 KST): replica를 1로 복원
- Night (18:00 KST): replica를 0으로 스케일 다운

**주요 특징**:
- CronJob은 `system` 노드에서만 실행
- KEDA ScaledObject는 별도로 일시정지/재개 (`targets.scaledObjects`)
- `external-secrets`, `istiod`, `aws-load-balancer-controller` 등 시스템 파드는 제외

#### Taint 적용

`app-general` NodePool에는 `workload=app:NoSchedule` taint를 적용하고, 실제 서비스 Deployment들에만 같은 toleration을 추가했습니다. 그래서 `external-secrets`, `istiod`, `aws-load-balancer-controller`, `kube-state-metrics` 같은 비앱 파드가 app 노드로 들어와 Karpenter scale down을 막는 상황을 줄일 수 있습니다.

주의할 점은 NodePool template 변경이 기존 노드의 taint를 자동으로 바꾸지는 않는다는 것입니다. 이미 생성된 app 노드에는 수동으로 taint를 넣거나 drain 후 교체가 필요합니다.

```sh
kubectl taint node <app-node-name> workload=app:NoSchedule
```

#### Karpenter 최적화

- `app-general` NodePool의 disruption budget은 최소 1대로 설정
- 비어있는 노드는 60초 후 자동 제거 (`consolidateAfter: 60s`)
- Spot 인스턴스 사용으로 비용 절감

#### KEDA 주의사항

KEDA가 붙은 서비스는 `targets.scaledObjects`에도 반드시 포함되어야 합니다. 그렇지 않으면 night 스케줄이 Deployment를 `0`으로 내려도 KEDA의 `minReplicaCount`가 다시 replica를 올려 app 노드 scale down이 막힐 수 있습니다.

### 장애 노드 복구

#### Terminating 파드 확인

```sh
./scripts/app-node-ops.sh list-terminating
```

#### Stuck 파드 강제 삭제

`auth-service`, `ticketing-service`의 stuck Terminating 파드 강제 삭제:

```sh
./scripts/app-node-ops.sh cleanup-terminating
```

특정 네임스페이스만:

```sh
./scripts/app-node-ops.sh cleanup-terminating truve-gateway-service
```

#### 노드 Drain

특정 노드 drain:

```sh
./scripts/app-node-ops.sh drain-node <node-name>
```