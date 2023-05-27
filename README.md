# q2Utils
qiime2を用いた解析パイプラインを自動化するためのシェルスクリプト。  
プライマー配列を除去済みのfastqファイルを入力とする。

## Contents
- q2Manif.sh マニフエストファイル作成
- q2Denoise.sh デノイジング 
- q2Classify.sh 系統推定 (classify-sklearn/classify-consensus-blastを選択可)
- q2Merge.sh 系統組成表作成
- q2Tree.sh 代表配列系統樹作成
- q2Pipe.sh  上記の内容を一括で実行

## Usage
- conda環境変数ファイルのパスとqiime2のconda環境名を指定することで、異なる解析環境でも実行可

```sh
# aruguments
CENV="${HOME}/miniconda3/etc/profile.d/conda.sh"
QENV='qiime2-2022.2'
REF='silva-138-99-nb-classifier.qza'

# paired-end
q2Pipe.sh -e $CNEV -q $QENV -a $REF -F 270 -R 200 -p ./fastq_dir

# single end
q2Pipe.sh -e $CNEV -q $QENV -a $REF -s ./fastq_dir

```

- リファレンスデータを分類機ではなく配列と系統データを指定すると、`classify-consensus-blast`を実行  

```sh
# arguments
CENV="${HOME}/miniconda3/etc/profile.d/conda.sh"
QENV='qiime2-2022.2'
FST=silva-138-99-seqs.qza 
TAX=silva-138-99-tax.qza

# qiime classify-consensus-blast
q2Pipe.sh -e $CNEV -q $QENV -a $REF -f $FST -x $TAX -s ./fastq_dir

```

## Results
- taxonomyランク毎に集計したカウントテーブル作成  

|taxon|S1|S2|S3|  
| :--- | :---: | :---: | ---: |  
| Unassigned | 6 | 0 | 8 |  
| p__Actinobacteriota | 29 | 0 | 7 | 
| p__Deinococcota | 316 | 180 | 54 |
  
  
- ノードラベルをtaxonomic-nameに変換したnewick形式の系統樹に変換 

```text
((((g__Allorhizobium-Neorhizobium-Pararhizobium-Rhizobium:0.038387286,( ..... ):3.024949999995072e-05)root;

```
