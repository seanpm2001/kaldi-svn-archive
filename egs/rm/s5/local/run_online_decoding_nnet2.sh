#!/bin/bash

. cmd.sh


stage=1
train_stage=-10
dir=exp/nnet2_online/nnet
use_gpu=true
. cmd.sh
. ./path.sh
. ./utils/parse_options.sh

if $use_gpu; then
  if ! cuda-compiled; then
    cat <<EOF && exit 1 
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA 
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.
EOF
  fi
  parallel_opts="-l gpu=1" 
  num_threads=1
  minibatch_size=512
  dir=exp/nnet2_online/nnet_gpu
else
  # Use 4 nnet jobs just like run_4d_gpu.sh so the results should be
  # almost the same, but this may be a little bit slow.
  num_threads=16
  minibatch_size=128
  parallel_opts="-pe smp $num_threads" 
  dir=exp/nnet2_online/nnet
fi


if [ $stage -le 1 ]; then
  mkdir -p exp/nnet2_online

  steps/online/nnet2/train_diag_ubm.sh --cmd "$train_cmd" --nj 10 --num-frames 200000 \
    data/train 512 exp/tri3b exp/nnet2_online/diag_ubm
fi

if [ $stage -le 2 ]; then
  steps/online/nnet2/train_ivector_extractor.sh --cmd "$train_cmd" --nj 4 \
    data/train exp/nnet2_online/diag_ubm exp/nnet2_online/extractor
fi

if [ $stage -le 3 ]; then
  steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj 4 \
    data/train exp/nnet2_online/extractor exp/nnet2_online/ivectors
fi


if [ $stage -le 4 ]; then
  steps/nnet2/train_pnorm_fast.sh --stage $train_stage \
    --splice-width 7 \
    --feat-type raw \
    --online-ivector-dir exp/nnet2_online/ivectors \
    --cmvn-opts "--norm-means=false --norm-vars=false" \
    --num-threads "$num_threads" \
    --minibatch-size "$minibatch_size" \
    --parallel-opts "$parallel_opts" \
    --num-jobs-nnet 4 \
    --num-epochs-extra 10 --add-layers-period 1 \
    --num-hidden-layers 2 \
    --mix-up 4000 \
    --initial-learning-rate 0.02 --final-learning-rate 0.004 \
    --cmd "$decode_cmd" \
    --pnorm-input-dim 1000 \
    --pnorm-output-dim 200 \
    data/train data/lang exp/tri3b_ali $dir  
fi

