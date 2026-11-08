# Jenkins controller for the local lab, fully configured from code:
#   plugins.txt -> plugins, casc.yaml -> users, credentials, agent, jobs.
# No clicking through the setup wizard; delete the container and you get the
# exact same Jenkins back.
FROM jenkins/jenkins:2.580.1-lts-jdk21

ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false" \
    CASC_JENKINS_CONFIG=/usr/share/jenkins/ref/casc.yaml

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

COPY casc.yaml /usr/share/jenkins/ref/casc.yaml
