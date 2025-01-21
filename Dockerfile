# Start with CUDA 12.1
FROM nvidia/cuda:12.1.1-cudnn8-devel-ubuntu22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Europe/London \
    PYTHONUNBUFFERED=1 \
    SHELL=/bin/bash \
    TORCH_VERSION=2.4.0+cu121 \
    XFORMERS_VERSION=0.0.27.post2 \
    INDEX_URL=https://download.pytorch.org/whl/cu121 \
    PYTHON_VERSION=3.11

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python${PYTHON_VERSION} \
    python${PYTHON_VERSION}-venv \
    python3-pip \
    git \
    wget \
    curl \
    nginx \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Install VS Code Server and configure it
RUN curl -fsSL https://code-server.dev/install.sh | sh

# Create VS Code configuration directory
RUN mkdir -p /root/.local/share/code-server/User/

# Copy VS Code settings
COPY settings.json /root/.local/share/code-server/User/settings.json

# Create directory structure
WORKDIR /workspace
RUN mkdir -p /workspace/ComfyUI \
    /workspace/custom_nodes \
    /workspace/models/{checkpoints,loras,embeddings,controlnet,vae}

# Clone ComfyUI at specific commit
ARG COMFYUI_COMMIT=a178e25912b01abf436eba1cfaab316ba02d272d
RUN git clone https://github.com/comfyanonymous/ComfyUI.git && \
    cd ComfyUI && \
    git checkout ${COMFYUI_COMMIT}

# Setup Python environment and install dependencies
RUN python${PYTHON_VERSION} -m pip install --upgrade pip && \
    python${PYTHON_VERSION} -m pip install \
    torch==${TORCH_VERSION} \
    torchvision \
    torchaudio \
    --index-url ${INDEX_URL} && \
    python${PYTHON_VERSION} -m pip install \
    xformers==${XFORMERS_VERSION}

# Install ComfyUI requirements
WORKDIR /workspace/ComfyUI
RUN pip install -r requirements.txt

# Install App Manager
ARG APP_MANAGER_VERSION=1.2.1
RUN mkdir -p /app-manager && \
    cd /app-manager && \
    wget https://github.com/ltdrdata/ComfyUI-Manager/archive/refs/tags/v${APP_MANAGER_VERSION}.zip && \
    unzip v${APP_MANAGER_VERSION}.zip && \
    mv ComfyUI-Manager-${APP_MANAGER_VERSION}/* /workspace/ComfyUI/custom_nodes/ComfyUI-Manager/ && \
    rm -rf /app-manager

# Install CivitAI Downloader
ARG CIVITAI_DOWNLOADER_VERSION=2.1.0
RUN mkdir -p /workspace/ComfyUI/custom_nodes/CivitAI-Browser && \
    cd /workspace/ComfyUI/custom_nodes/CivitAI-Browser && \
    wget https://github.com/civitai/ComfyUI-CivitAI-Browser/archive/refs/tags/v${CIVITAI_DOWNLOADER_VERSION}.zip && \
    unzip v${CIVITAI_DOWNLOADER_VERSION}.zip && \
    mv ComfyUI-CivitAI-Browser-${CIVITAI_DOWNLOADER_VERSION}/* . && \
    rm v${CIVITAI_DOWNLOADER_VERSION}.zip

# Configure nginx
COPY nginx.conf /etc/nginx/nginx.conf
COPY 502.html /usr/share/nginx/html/502.html

# Create startup script
RUN echo '#!/bin/bash\n\
# Start nginx\n\
service nginx start\n\
\n\
# Start VS Code Server\n\
code-server --bind-addr 0.0.0.0:8080 --auth none & \n\
\n\
# Start ComfyUI\n\
cd /workspace/ComfyUI\n\
python3 main.py --listen 0.0.0.0 --port 8188\n\
' > /workspace/start.sh && chmod +x /workspace/start.sh

EXPOSE 8188 8080

WORKDIR /workspace
CMD ["/workspace/start.sh"]