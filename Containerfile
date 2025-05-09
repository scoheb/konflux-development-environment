FROM quay.io/konflux-ci/release-service-utils:7d75854c27afb4ece1e7e5428bca0799220b52de

COPY delete-expired-clusters.sh /usr/local/bin/delete-expired-clusters.sh
COPY hypershift-delete-cluster.sh /usr/local/bin/hypershift-delete-cluster.sh
COPY notify.sh /usr/local/bin/notify.sh

# Install AWSCLI
RUN pip install --upgrade pip && \
    pip install --upgrade awscli

# install HCP
RUN curl https://hcp-cli-download-multicluster-engine.apps.collective.aws.red-chesterfield.com/linux/amd64/hcp.tar.gz \
    --output /tmp/hcp.tgz && tar xvzf /tmp/hcp.tgz --directory=/usr/local/bin

ENTRYPOINT [ "/usr/local/bin/delete-expired-clusters.sh" ]
