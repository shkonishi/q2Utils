# q2Utils
qiime2を用いた解析パイプラインを自動化するためのシェルスクリプト。  
プライマー配列を除去済みのfastqファイルを入力とする。

## Contents
- q2Manif.sh マニフエストファイル作成
- q2Denoise.sh デノイジング 
- q2Classify.sh 系統推定 
- q2Merge.sh 系統組成表作成, 代表配列系統樹作成 
- q2Pipe.sh  上記の内容を一括で実行

## Usage
- conda環境変数ファイルのパスとqiime2のconda環境名を指定することで、異なる解析環境でも実行可

```sh
CENV="${HOME}/miniconda3/etc/profile.d/conda.sh"
QENV='qiime2-2022.2'
REF='silva-138-99-nb-classifier.qza'

# paired-end
bash q2Pipe.sh -e $CNEV -q $QENV -a $REF -F 270 -R 200 -p ./fastq_dir

# single end
bash q2Pipe.sh -e $CNEV -q $QENV -a $REF -s ./fastq_dir

```

- リファレンスデータを分類機ではなく配列と系統データを指定すると、`classify-consensus-blast`を実行  

```sh
CENV="${HOME}/miniconda3/etc/profile.d/conda.sh"
QENV='qiime2-2022.2'
FST=silva-138-99-seqs.qza 
TAX=silva-138-99-tax.qza

bash q2Pipe.sh -e $CNEV -q $QENV -a $REF -f $FST -x $TAX -s ./fastq_dir

```
