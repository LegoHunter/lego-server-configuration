# Setup a new github repo with a deployable service

1. go to github.com
2. goto `LegoHunter`Repositories https://github.com/orgs/LegoHunter/repositories
3. Click `New Repository`
4. Add .gitignore for Java
5. Add README
6. Click `Create Repository`
7. **_Ensure repository is Public, or github actions vars and secrets will not work_**
7. Create `develop` branch by clicking `main` branch dropdown and select `Create develop from main`
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
18. Java `21`
19. Add Dependencies: `Lombok`, `Spring Configuration Processor`, `Spring Web`, `Spring Security`, `MyBatis Framework`, `MySQL Driver`, `Spring Boot Actuator`, `Distributed Tracing`, `Zipkin`, `Resilience4J`
20. Shortcut : https://start.spring.io/#!type=maven-project&language=java&platformVersion=3.3.4&packaging=jar&jvmVersion=21&groupId=net.legohunter&artifactId=sandbox-service&name=sandbox-service&description=Demo%20project%20for%20Spring%20Boot&packageName=net.legohunter.sandbox.service&dependencies=lombok,configuration-processor,web,security,mybatis,mysql,actuator,distributed-tracing,zipkin,cloud-resilience4j
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
29. Commit and Push to github a new feature branch 
30. Switch to new feature branch 
29. Create `.github` top-level folder
30. Create `workflows` folder under `.github`
31. Copy `kubernetes` folder from another deployable application.
32. Edit `deployment.yml` as needed
33. Edit `lb-service.yml` as needed - ensure `spec.ports.port` is unique
34. login to `quay.com`
35. Create new repository with service name
36. Ensure repository is public
37. Goto repository settings and add the `tvattima+github` Robot User with Write permissions
32. Copy `feature-branch-mvn-deploy-snapshot.yml` from another deployable application.
33. Edit `feature-branch-mvn-deploy-snapshot.yml` to reflect service's name, etc.
34. Commit and Push to github feature branch created in previous step
35. Will fail first time, but image should be pushed to quay repository (check that is the case)
36. On Windows machine, run the following commands:
```shell
cd to root of repository
kubectl apply -f .\kubernetes\deployment.yml
kubectl apply -f .\kubernetes\lb-service.yml
```
Application should now be running in Kubernetes cluster on port defined in `lb-service.yml`
