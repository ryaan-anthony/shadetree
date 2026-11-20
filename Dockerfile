# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. The Deploy workflow
# (.github/workflows/deploy.yml, ops/deploy/deploy.sh) builds and runs it on each environment's VM;
# Deploy CI (.github/workflows/deploy-ci.yml) builds and checks it on every relevant PR. Build by hand:
# docker build -t shadetree .

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=4.0.9
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages (chromium prints quote and invoice PDFs, ADR 0010)
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips postgresql-client chromium fonts-liberation fonts-noto-cjk && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    BROWSER_PATH="/usr/bin/chromium"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy application code
COPY . .
# Uploaded files and the backup status file live under storage/, a Docker volume in the deployment
# (ADR 0023). Created here so a new volume starts owned by the app user.
RUN mkdir -p storage/backup

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile




# Final stage for app image
FROM base

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Run as a non-root user that owns only what it writes at runtime: storage/ (the volume), tmp/ and
# log/. The code and gems belong to root, so a compromised app process can't change what it runs.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /usr/sbin/nologin && \
    chown -R rails:rails log storage tmp
USER 1000:1000

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Puma directly (ADR 0023): it serves HTTPS on 3443 with the Cloudflare Origin CA certificate for
# the tunnel when TLS_CERT_BASE64 and TLS_KEY_BASE64 are set (config/puma.rb); 3000 is plain HTTP
# for health checks inside the container and is never published.
ENV PORT="3000"
EXPOSE 3000 3443
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
