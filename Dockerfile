# Use NVIDIA's official CUDA image with Ubuntu 22.04
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

# Set non-interactive mode for apt
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    wget \
    git \
    sudo \
    espeak-ng \
    build-essential \
    cmake \
    && rm -rf /var/lib/apt/lists/*

# Install Miniconda
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh && \
    bash miniconda.sh -b -p /opt/conda && \
    rm miniconda.sh
ENV PATH=/opt/conda/bin:$PATH

# Create and activate conda environment
RUN conda create -n vevo python=3.10 -y

# Set default shell to use conda env
SHELL ["conda", "run", "-n", "vevo", "/bin/bash", "-c"]

# Install core build tools and pip tools for source packages like fastdtw
RUN pip install --upgrade pip setuptools wheel cython

# Clone custom Amphion repo
WORKDIR /workspace
RUN git clone https://github.com/zelin/Amphion.git
WORKDIR /workspace/Amphion

# Run Amphion's environment setup script (may install fastdtw, etc.)
RUN bash env.sh

# Install additional requirements for VEVO
RUN pip install -r models/vc/vevo/requirements.txt

# Install boto3 for AWS access
RUN pip install boto3

# Set working directory for inference
WORKDIR /workspace/Amphion

# Default entrypoint to run your worker script
ENTRYPOINT ["conda", "run", "--no-capture-output", "-n", "vevo", "python", "run_inference_worker.py"]
