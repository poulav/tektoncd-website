# Stage 1: Build environment
FROM node:lts-alpine3.22 AS builder

# Install build dependencies
RUN apk add --update --no-cache \
    build-base \
    git \
    python3 \
    py3-pip \
    python3-dev \
    curl \
    wget

# Install Hugo extended manually (supports both ARM64 and AMD64)
# RUN ARCH=$(uname -m) && \
#     if [ "$ARCH" = "x86_64" ]; then \
#         HUGO_ARCH="amd64"; \
#     elif [ "$ARCH" = "aarch64" ]; then \
#         HUGO_ARCH="arm64"; \
#     else \
#         echo "Unsupported architecture: $ARCH" && exit 1; \
#     fi && \
#     HUGO_VERSION="0.118.2" && \
#     wget -O hugo.tar.gz "https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_linux-${HUGO_ARCH}.tar.gz" && \
#     tar -xzf hugo.tar.gz && \
#     mv hugo /usr/local/bin/ && \
#     rm hugo.tar.gz

# RUN chmod +x /usr/local/bin/hugo
# ENV PATH="/usr/local/bin:${PATH}"

WORKDIR /app

# Copy package files and install Node.js dependencies
COPY package*.json ./
RUN npm cache clean --force
RUN npm install

# Copy source code
COPY . .

# Configure git
RUN git config --global --add safe.directory /app

# Install Python dependencies
RUN python3 -m venv .venv && \
    . .venv/bin/activate && \
    pip install --upgrade pip && \
    pip install -r requirements.txt

# Install netlify-cli
RUN npm install -g netlify-cli

FROM hugomods/hugo:latest as hugoapp

WORKDIR /app

RUN hugo mod get
RUN hugo mod tidy

COPY . .

RUN hugo

# Stage 2: Runtime environment
FROM node:lts-bullseye AS runtime

# Install only runtime dependencies
RUN apt-get update && \
    apt-get install -y git python3 python3-venv && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src

# Copy Hugo binary from builder
# COPY --from=hugoapp /usr/local/bin/hugo /usr/local/bin/hugo
COPY --from=hugoapp /app /src/

# Copy everything from builder stage
COPY --from=builder /app/package*.json /src/
COPY --from=builder /app/node_modules /src/node_modules
COPY --from=builder /app/content /src/content
COPY --from=builder /app/requirements.txt /src/
COPY --from=builder /app/.venv /src/.venv
COPY --from=builder /app/config.* /src/
COPY --from=builder /app/static /src/static
COPY --from=builder /usr/local/lib/node_modules/netlify-cli /usr/local/lib/node_modules/netlify-cli
# COPY --from=builder /usr/local/bin/netlify /usr/local/bin/netlify

RUN adduser --uid 1020 --gid 0 --shell /bin/sh hugo
RUN chown -R hugo:root /src
# RUN cat /etc/passwd

USER hugo

ENV PATH="/usr/local/bin:${PATH}" \
    NODE_PATH="/usr/local/lib/node_modules"

ENTRYPOINT ["node", "/usr/local/lib/node_modules/netlify-cli/bin/run"]
CMD ["dev"]