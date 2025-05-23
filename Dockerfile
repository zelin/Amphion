# Use NVIDIA's official CUDA image with Ubuntu 22.04
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04
# FROM cnstark/pytorch:2.0.1-py3.10.11-cuda11.8.0-ubuntu22.04

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
# Add a dummy build arg to force a cache bust
ARG AMPHION_REF=main

# Clone Amphion repo with cache busting
RUN rm -rf Amphion && \
    git clone --depth=1 https://github.com/zelin/Amphion.git --branch ${AMPHION_REF}
WORKDIR /workspace/Amphion

# Install AWS SDK
RUN pip install boto3

# Run Amphion's environment setup script

RUN set -e && \
    echo "🔧 Installing ffmpeg via conda..." && \
    conda install -c conda-forge ffmpeg -y

RUN set -e && \
    echo "📦 Installing pip packages..." && \
    pip install \
    setuptools ruamel.yaml tqdm colorama easydict tabulate loguru json5 Cython unidecode inflect argparse g2p_en tgt librosa==0.9.1 matplotlib typeguard einops omegaconf hydra-core humanfriendly pandas munch

RUN set -e && \
    echo "📦 Installing tensor packages..." && \
    pip install \
    tensorboard tensorboardX torch==2.0.1 torchaudio==2.0.2 torchvision==0.15.2 accelerate==0.24.1 transformers==4.41.2 diffusers praat-parselmouth audiomentations pedalboard ffmpeg-python==0.2.0 pyworld diffsptk==1.0.1 nnAudio ptwt

RUN set -e && \
    echo "📦 Installing encodec packages..." && \
    pip install \
    encodec vocos speechtokenizer descript-audio-codec

RUN set -e && \
    echo "📦 Installing python-pesq packages..." && \
    pip install \
    https://github.com/vBaiCai/python-pesq/archive/master.zip

RUN set -e && \
    echo "📦 Installing lhotse packages..." && \
    pip install \
    git+https://github.com/lhotse-speech/lhotse

RUN set -e && \
    echo "📦 Installing encodec..." && \
    pip install \
    -U encodec

RUN set -e && \
    echo "📦 Installing phonemizer..." && \
    pip install \
    phonemizer==3.2.1 pypinyin==0.48.0 black==24.1.1

RUN set -e && \
    echo "📦 Installing torchmetrics packages..." && \
    pip install \
    torchmetrics

RUN set -e && \
    echo "📦 Installing openai packages..." && \
    pip install \
    openai-whisper frechet_audio_distance asteroid resemblyzer vector-quantize-pytorch==1.12.5

# RUN set -e && \
#     echo "📦 Installing pymcd packages..." && \
#     pip install \
#     -U pymcd 
# Install any additional VEVO-specific requirements
RUN pip install -r models/vc/vevo/requirements.txt

# Entrypoint for inference
ENTRYPOINT ["conda", "run", "--no-capture-output", "-n", "vevo", "python", "run_inference_worker.py"]