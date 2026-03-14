FROM perl:5.40-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential libssl-dev \
    && rm -rf /var/lib/apt/lists/*

ARG KARR_TGZ="App-karr.tar.gz"

COPY ${KARR_TGZ} /tmp/karr.tar.gz

RUN tar -xzf /tmp/karr.tar.gz -C /tmp --strip-components=1 \
    && cpanm --notest --installdeps /tmp \
    && cpanm --notest /tmp/karr.tar.gz \
    && rm -rf /tmp/*

FROM perl:5.40-slim

COPY --from=builder /usr/local/lib/perl5/site_perl/ /usr/local/lib/perl5/site_perl/
COPY --from=builder /usr/local/bin/ /usr/local/bin/

ENTRYPOINT ["karr"]
