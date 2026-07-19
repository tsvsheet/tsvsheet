# Pinned ANTLR4 generator. The Java toolchain is isolated here; only someone
# regenerating parsers from the .g4 grammars needs Docker. Generated parsers
# are committed in each implementation, so their normal builds stay Docker-free.
FROM eclipse-temurin:21-jre

ARG ANTLR_VERSION=4.13.2
ADD https://www.antlr.org/download/antlr-${ANTLR_VERSION}-complete.jar /antlr.jar

WORKDIR /work
ENTRYPOINT ["java", "-jar", "/antlr.jar"]
