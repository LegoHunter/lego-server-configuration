# Setup a new github repo with a deployable service

1. go to github.com
2. goto `LegoHunter`Repositories https://github.com/orgs/LegoHunter/repositories
3. Click `New Repository`
4. Add .gitignore for Java
5. Add README
6. Click `Create Repository`
7. **_Ensure repository is Public, or github actions vars and secrets will not work_**
7. Click Create Repository 
7. Create `main` branch by clicking `develop` branch dropdown and select `Create main from develop`
8. Click Repository `Settings` on main toolbar
9. Edit the Default branch to be develop 
10. Back on Windows machine, cd to `d:/dev/projects/lego-collection`
11. clone new repository: `git clone <repo-url>`
12. Create sandbox springboot project: https://start.spring.io
13. Select `Maven` and latest Spring Boot release version
14. Group: `net.legohunter`
15. Artifact `<service-name>`
16. Update `Description`
17. Update `Package name`
18. Java `21` (LCMS standard LTS; see [Service standard](#service-standard-homelab-26))
19. Add Dependencies: `Lombok`, `Spring Configuration Processor`, `Spring Web`, `Spring Security`, `MyBatis Framework`, `MySQL Driver`, `Spring Boot Actuator`, `Distributed Tracing`, `Zipkin`, `Resilience4J`
20. Shortcut : https://start.spring.io/#!type=maven-project&language=java&platformVersion=3.5.10&packaging=jar&configurationFileFormat=properties&jvmVersion=21&groupId=io.legohunter&artifactId=external-service-catalog-processor&name=External%20Service%20Catalog%20Processor&description=Processes%20External%20Service%20Catalogs&packageName=io.legohunter.job&dependencies=lombok,configuration-processor,security,mybatis,mysql,actuator,distributed-tracing,cloud-resilience4j,prometheus,otlp-metrics
21. Click `Generate`
22. Expand downloaded zip file into cloned directory from previous step.
23. In IntelliJ, expand new module folder, and right-click `pom.xml` and select `Import As Maven Project`
24. Edit `<name>` in `pom.xml` as needed
25. Add `aspectj` and `mockito` test libraries to `pom.xml`
   ```
   		<dependency>
   			<groupId>org.assertj</groupId>
   			<artifactId>assertj-core</artifactId>
   			<scope>test</scope>
   		</dependency>
   		<dependency>
   			<groupId>org.mockito</groupId>
   			<artifactId>mockito-core</artifactId>
   			<scope>test</scope>
   		</dependency>
   ```
25. Add `<github.organization>LegoHunter</github.organization>` to pom.xml properties 
26. Add `<distributionManagement>` and `<repositories>` to pom.xml
```
    <distributionManagement>
        <repository>
            <id>github</id>
            <name>GitHub Packages</name>
            <url>https://maven.pkg.github.com/${github.organization}/${project.artifactId}</url>
        </repository>
    </distributionManagement>

    <repositories>
        <repository>
            <id>central</id>
            <url>https://repo1.maven.org/maven2</url>
        </repository>
        <repository>
            <id>github</id>
            <url>https://maven.pkg.github.com/${github.organization}/*</url>
            <snapshots>
                <enabled>true</enabled>
            </snapshots>
        </repository>
    </repositories>
```
26. Ensure project builds with `mvn clean install`

May have to change `@SpringBootApplication` to:

```java
@SpringBootApplication(exclude = {
        DataSourceAutoConfiguration.class
})
```

27. Ensure application runs locally in IntelliJ
28. Hit application in browser: `http://localhost:8080/actuator/health`
29. Commit and push a new feature branch named `feature/<JIRA>-<slug>`.
30. Create the Quay repository: log in to `quay.io`, create a **public** repository named after the
    service, and give the `tvattima+github` robot user **Write** permission.
31. Add the Kubernetes manifests and the CI caller described in [Service standard](#service-standard-homelab-26).
32. Push the feature branch. The push builds, tests and deploys the branch to `services-sandbox`;
    check the run, then `https://<service>.sandbox.internal.legohunter.io/actuator/health`.
33. Allow the deploy runner into each namespace the service deploys to: the `arc-deployer`
    RoleBinding in [../github-runner/rbac/arc-deployer.yaml](../github-runner/rbac/arc-deployer.yaml)
    (today only `services-sandbox` exists).

## Service standard (HOMELAB-26)

Every Kubernetes-deployed LCMS service follows this layout so the shared pipeline can build and
deploy it without per-service CI code. `lego-data-service` and `lego-data-ingress` are the
reference implementations.

### Environments

| Event | What runs | Target |
| --- | --- | --- |
| push to `feature/**` | tests, image `quay.io/tvattima/<service>:<pushed sha>` (expires after 26 weeks), deploy | `services-sandbox` (the live preview of the feature branch being worked on; the latest push wins) |
| PR `feature/*` -> `develop` | tests only, on the branch merged with the latest `develop` | - |
| PR merged into `develop` | tests on the merge commit, then the **only** image build for that commit: `quay.io/tvattima/<service>:dev-<merge sha>` (no expiry), deployed by digest - only if `DEPLOY_DEV_ENABLED` is `true` | `services-dev` |
| PR `develop` -> `main` merged | **no rebuild** (build once, promote by digest): checks `main` has exactly the code of the merged `develop` commit, adds the tag `prod-<main sha>` to that commit's DEV image and deploys the same digest - only if `DEPLOY_PROD_ENABLED` is `true`. Fails if DEV never built that commit. | `services-prod` |

Every deploy pins the image by digest (`quay.io/tvattima/<service>@sha256:...`), so PROD runs
byte-for-byte the image DEV ran. Consequences: release to PROD only by merging `develop` into `main`
(never commit to `main` directly), and keep the DEV gate open whenever the PROD gate is open.

A feature push or PR that changes only documentation (`*.md`, `docs/**`, `LICENSE`) skips the
build, tests, image and deploy; merges into `develop`/`main` are never skipped. Each environment
deploys one run at a time per service. The services build with `mvn verify` (their Maven artifacts
are not published to GitHub Packages; only libraries publish).

### Repository layout

```
.github/workflows/build-test-deploy.yml   thin caller (below)
kubernetes/Containerfile
kubernetes/base/{deployment,service,ingress,kustomization}.yaml
kubernetes/overlays/{sandbox,dev,prod}/
src/main/resources/application.yml
src/main/resources/application-{sandbox,dev,prod,kubernetes}.yml
```

### CI caller

Copy this to `.github/workflows/build-test-deploy.yml` and change only `app`:

```yaml
name: Build Test Deploy

on:
  push:
    branches:
      - 'feature/**'
  pull_request:
    branches:
      - develop
      - main
    types:
      - opened
      - reopened
      - synchronize
      - closed

permissions:
  contents: read
  packages: write

jobs:
  pipeline:
    uses: LegoHunter/lego-server-configuration/.github/workflows/k8s-service-pipeline.yml@develop
    with:
      app: <service>
      java-version: '21'
      quay-username: ${{ vars.QUAY_USERNAME }}
      deploy-dev-enabled: ${{ vars.DEPLOY_DEV_ENABLED == 'true' }}
      deploy-prod-enabled: ${{ vars.DEPLOY_PROD_ENABLED == 'true' }}
    secrets:
      QUAY_TOKEN: ${{ secrets.QUAY_TOKEN }}
```

The pipeline itself is [../.github/workflows/k8s-service-pipeline.yml](../.github/workflows/k8s-service-pipeline.yml).
`QUAY_USERNAME` (variable) and `QUAY_TOKEN` (secret) are shared by the existing services and are
not set per repository, so they are most likely LegoHunter organization settings.
`DEPLOY_DEV_ENABLED` / `DEPLOY_PROD_ENABLED` are unset (gates shut) until the target namespace,
its ExternalSecret, the `arc-deployer` RoleBinding and the environment's database exist.

To trial a pipeline change, point one service's feature branch at the pipeline's feature branch
(`...k8s-service-pipeline.yml@feature/<branch>`), and switch back to `@develop` before merging.

### Containerfile

```dockerfile
FROM amazoncorretto:21-alpine-jdk
ARG JAR_FILE=target/*.jar
COPY ${JAR_FILE} app.jar
ENTRYPOINT ["java","-jar","/app.jar"]
```

* Java 21 LTS, in step with `<java.version>21</java.version>` in `pom.xml` and the caller's `java-version`.
* No `-Dspring.profiles.active`: Spring reads `SPRING_PROFILES_ACTIVE` from the environment.
* No `quay.expires-after` label: the pipeline adds it to sandbox images only, so DEV/PROD images never expire.

### Kubernetes overlays

The pipeline renders `kubernetes/overlays/<env>`, swaps the image tag for `quay.io/tvattima/<service>:...`,
applies it to `services-<env>` and restarts `deployment/<service>`. Each overlay sets:

* `namespace: services-<env>` and the label `app.kubernetes.io/instance: <env>` (pod template too);
* `SPRING_PROFILES_ACTIVE=<env>,kubernetes` (`deployment-env-patch.yaml`);
* the ExternalSecret `services-<env>-external-secret`, mounted at `/etc/.credentials`;
* host `<service>.<env>.internal.legohunter.io` with TLS secret `<env>-internal-legohunter-io-tls`.

### Spring profiles

* `application-<env>.yml` per environment: its own `spring.config.import` of the mounted
  credential files, `spring.datasource.database-key-name: rasppi5-01-lego-<env>`, and any
  environment-specific topics, buckets and endpoints. Never point a non-PROD profile at PROD data,
  or the PROD profile at `rasppi5-01-lego-prod-legacy`.
* `application-kubernetes.yml`: only in-cluster settings shared by every environment
  (`import-path: /etc/.credentials`, actuator/probes, OTEL endpoints).
* Only `application-prod.yml` sets `lego.environment.production: true`.

### Tests

Copy the consistency tests from `lego-data-service` (`src/test/java/.../config/`):
`KubernetesOverlayTest` (every overlay targets its own namespace, instance, profile, secret, host
and TLS) and `SpringProfileEnvironmentTest` (every profile uses its own database key and imports).

## Library standard (HOMELAB-26)

Every LCMS Maven library (published to GitHub Packages, consumed by services or other libraries)
calls the shared library pipeline instead of carrying its own CI code. Libraries have no
environments: they publish a `-SNAPSHOT` of the version in their `pom.xml`.

| Event | What runs |
| --- | --- |
| push to `feature/**` | `mvn deploy`: tests, then publish the SNAPSHOT (so another repo can pick up a feature-branch change without a PR) |
| PR -> `develop` | `mvn verify` only, on the branch merged with the latest `develop`; nothing is published |
| push to `develop` (a merge) | `mvn deploy` from `develop`, so the published SNAPSHOT returns to the merged code |

The latest push to any of those branches wins the SNAPSHOT. `main`/`master` pushes publish nothing.
Docs-only pushes and PRs (`*.md`, `docs/**`, `LICENSE`) skip tests and publishing, and publishes
run one at a time per branch.

Copy this to `.github/workflows/build-test-deploy.yml`:

```yaml
name: Build Test Deploy

on:
  push:
    branches:
      - 'feature/**'
      - develop
  pull_request:
    branches:
      - develop
    types:
      - opened
      - reopened
      - synchronize

permissions:
  contents: read
  packages: write

jobs:
  pipeline:
    uses: LegoHunter/lego-server-configuration/.github/workflows/maven-library-pipeline.yml@develop
    with:
      java-version: '21'
```

* Java 21 LTS, in step with `<java.version>21</java.version>` and `<release>${java.version}</release>`
  in `pom.xml`. A different `java-version` is an exception and must name its ticket in a comment
  (today: `bricklink-html`, `bricklink-inventory`, `bricklink-fulfillment` stay on 22 until
  HOMELAB-27 moves them and `lego-command` onto the current libraries).
* `pom.xml` needs `distributionManagement` for `https://maven.pkg.github.com/LegoHunter/<repo>`
  with server id `github` (the id `setup-java` writes into `settings.xml`).
* `.gitignore` excludes `target/`.

The pipeline itself is [../.github/workflows/maven-library-pipeline.yml](../.github/workflows/maven-library-pipeline.yml).
Trial a change the same way as the service pipeline: point one library's feature branch at
`...maven-library-pipeline.yml@feature/<branch>` and switch back to `@develop` before merging.
