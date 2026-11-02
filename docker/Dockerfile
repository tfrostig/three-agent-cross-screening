FROM rocker/r-ver:4.6.0@sha256:6f05a1a8b8c52328f181593923909b01cbfd14c9caea93bf75ddc65e806d8eac
COPY docker/install.R /opt/runner/install.R
RUN Rscript --vanilla /opt/runner/install.R && rm /opt/runner/install.R
COPY R/contracts.R /opt/runner/contracts.R
COPY docker/runtime.R /opt/runner/runtime.R
RUN mkdir -p /work /output && chmod 1777 /work /output
ENV HOME=/tmp R_ENVIRON_USER=/dev/null R_PROFILE_USER=/dev/null
WORKDIR /work
USER 65534:65534
ENTRYPOINT ["Rscript", "--vanilla", "/opt/runner/runtime.R"]
