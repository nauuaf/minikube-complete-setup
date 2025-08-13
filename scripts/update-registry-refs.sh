#!/bin/bash
source config/config.env

mkdir -p /tmp/updated-apps

# Function to update manifests
update_manifest() {
    local input_file=$1
    local output_file=$2
    
    # Check if we should use local images or registry
    if [ "${USE_LOCAL_IMAGES:-false}" = "true" ]; then
        # Use local images without registry
        sed -e 's|image: .*api-service:.*|image: api-service:1.0.0|' \
            -e 's|image: .*auth-service:.*|image: auth-service:1.0.0|' \
            -e 's|image: .*image-service:.*|image: image-service:1.0.0|' \
            -e 's|image: .*frontend:.*|image: frontend:1.0.0|' \
            -e 's|imagePullPolicy: Always|imagePullPolicy: IfNotPresent|' \
            "$input_file" > "$output_file"
    else
        # Use cluster registry
        sed -e 's|image: localhost:30500/|image: docker-registry.default.svc.cluster.local:5000/|' \
            -e 's|imagePullPolicy: Always|imagePullPolicy: IfNotPresent|' \
            "$input_file" > "$output_file"
    fi
}

# Update all application manifests
for file in kubernetes/apps/*.yaml; do
    basename=$(basename "$file")
    update_manifest "$file" "/tmp/updated-apps/$basename"
    echo "Updated $basename"
done

echo "Registry references updated"
