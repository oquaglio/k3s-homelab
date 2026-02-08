FROM flink:1.20

# Download Kafka connector JARs at build time so they're baked into the image
ARG FLINK_KAFKA_CONNECTOR_VERSION=3.3.0-1.20
ARG KAFKA_CLIENTS_VERSION=3.7.1

RUN wget -q -P /opt/flink/lib/ \
      "https://repo1.maven.org/maven2/org/apache/flink/flink-connector-kafka/${FLINK_KAFKA_CONNECTOR_VERSION}/flink-connector-kafka-${FLINK_KAFKA_CONNECTOR_VERSION}.jar" && \
    wget -q -P /opt/flink/lib/ \
      "https://repo1.maven.org/maven2/org/apache/kafka/kafka-clients/${KAFKA_CLIENTS_VERSION}/kafka-clients-${KAFKA_CLIENTS_VERSION}.jar" && \
    echo "Kafka JARs installed:" && ls -la /opt/flink/lib/kafka* /opt/flink/lib/flink-connector-kafka*
