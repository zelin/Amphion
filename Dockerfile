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
SHELL ["conda", "run", "-n", "vevo", "/bin/bash", "-c"]

# Clone Amphion repo
WORKDIR /workspace
RUN git clone https://github.com/zelin/Amphion.git
WORKDIR /workspace/Amphion

# Modify env.sh to remove fairseq installation
RUN sed -i '/pip install fairseq/d' env.sh

# Run environment setup
RUN bash env.sh

# Install additional VEVO model requirements
RUN pip install -r models/vc/vevo/requirements.txt

# Install boto3 (missing dependency)
RUN conda run -n vevo pip install boto3

# Set working directory
WORKDIR /workspace/Amphion

# Entrypoint to run your main.py
ENTRYPOINT ["conda", "run", "--no-capture-output", "-n", "vevo", "python", "run_inference_worker.py"]