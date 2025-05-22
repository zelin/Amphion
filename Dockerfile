# Use NVIDIA's official CUDA image with Ubuntu 22.04
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

# Set non-interactive mode for apt
ENV DEBIAN_FRONTEND=noninteractive

# Use Tencent mirrors for faster APT in China (optional)
RUN apt-get update && \
    apt-get install -y \
    wget \
    git \
    sudo \
    espeak-ng \
    build-essential \
    cmake && \
    rm -rf /var/lib/apt/lists/*

# Install Miniconda
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh && \
    bash miniconda.sh -b -p /opt/conda && \
    rm miniconda.sh
ENV PATH=/opt/conda/bin:$PATH

# Create and activate conda environment
RUN conda create -n vevo python=3.10 -y

# Use conda environment for all remaining commands
SHELL ["conda", "run", "-n", "vevo", "/bin/bash", "-c"]

# Clone custom Amphion repo (your fork)
WORKDIR /workspace
RUN git clone https://github.com/zelin/Amphion.git
WORKDIR /workspace/Amphion

# Install AWS SDK
RUN pip install boto3

# Run Amphion's environment setup script
RUN bash env.sh

# Install any additional VEVO-specific requirements
# RUN pip install -r models/vc/vevo/requirements.txt

# Entrypoint for inference
ENTRYPOINT ["conda", "run", "--no-capture-output", "-n", "vevo", "python", "run_inference_worker.py"]