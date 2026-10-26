variable "VERSION" {
  default = "dev"
}

variable "GIT_SHA" {
  default = "unknown"
}

variable "REGISTRY" {
  default = "localhost:5000"
}

target "_common" {
  labels = {
    "org.opencontainers.image.version" = "${VERSION}"
    "org.opencontainers.image.revision" = "${GIT_SHA}"
  }
  platforms = ["linux/amd64", "linux/arm64"]
  cache-from = ["type=registry,ref=${REGISTRY}/cache:worker"]
  cache-to = ["type=registry,ref=${REGISTRY}/cache:worker,mode=max"]
}

group "default" {
  targets = ["api", "worker"]
}

target "api" {
  inherits = ["_common"]
  context = "../tp01-optimisation-image/starter/shopapi"
  dockerfile = "Dockerfile"
  target = "production"
  tags = ["${REGISTRY}/shop-api:${VERSION}"]
}

target "worker" {
  inherits = ["_common"]
  context = "./starter/shop-worker"
  dockerfile = "Dockerfile"
  target = "runtime"
  tags = ["${REGISTRY}/shop-worker:${VERSION}"]
  secret = ["id=pipconf,src=./starter/shop-worker/pip.conf"]
}

target "worker-test" {
  inherits = ["_common"]
  context = "./starter/shop-worker"
  dockerfile = "Dockerfile"
  target = "test"
  tags = ["${REGISTRY}/shop-worker:test-${VERSION}"]
  secret = ["id=pipconf,src=./starter/shop-worker/pip.conf"]
}

