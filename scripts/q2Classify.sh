#!/bin/bash
VERSION=0.1.230302
AUTHOR=SHOGO_KONISHI
CMDNAME=`basename $0`

### <CONTENTS> qiime feature-classifierを用いて系統推定 ###
# 1. ドキュメント
# 2. オプション引数の処理
## 2.1. オプション引数の入力
## 2.2. オプション引数の判定
# 3. コマンドライン引数の処理
# 4. 引数の一覧
# 5. メイン
## 5.1. qiime2 起動
## 5.2. qiime feature-lassifierを実行
## 5.3. taxonomyテーブルをqzv形式とテキストファイルに変換
## 5.4. 棒グラフを作成　qiime taxa barplot

# 1. ドキュメント
## 1.1. ヘルプの表示
function print_doc() {
cat << EOS
使用法:
    $CMDNAME [オプション] <repset.qza> <table.qza>

用語の定義およびこのプログラム中で使用されるデフォルトファイル名:
    ASV                Denoisingされた配列. dada2の出力 [repset.qza]
    ASVテーブル         検体に含まれるASVの存在量. dada2の出力 [table.qza]
    taxonomyテーブル    ASVの系統推定結果. qiime feature-classifierの出力 [taxonomy.qza]
    系統組成表          taxonomyテーブルとASVテーブルを結合したもの [taxtab.txt]

説明:
    このプログラムはqiime2を用いてASVの系統推定を実施します。
    入力ファイルとして、dada2を用いたdenoising後のASVファイル(qza形式)とASVテーブル(qza形式)を指定します。

    系統推定手法はsklearn/blastいずれかが選択されます(vsearchはdenoisingのプロセスが異なるので含めていません)。
    分類機を指定するか([-a]オプションで指定)、リファレンス配列および系統データ([-f],[-x]オプションで指定)を指定するかで、
    どちらを実行するかが判定されます。

    分類機は配布されているものか、qiime feature-classifierを実行して得られたqzaファイルを指定します。
    リファレンス配列ファイルと、それに対応するtaxonomyデータのファイルは、いずれもqzaでインポートしたものを指定します。
    分類機およびリファレンスデータファイルはファイルパスで指定するか、環境変数'Q2DB'を指定しておけばファイル名で指定できます。

    結果として得られたtaxonomyテーブルとASVテーブル(qza形式)を用いて、
    系統組成の棒グラフ(qzv形式)を作成します。その際オプションとしてメタデータのファイル[default:map.txt]を指定することができます。

    デフォルトの出力ファイル名は以下のようになっています。
        taxonomy.qza        [ASV系統推定結果]
        taxonomy.qzv        [ASV系統推定結果をqzvに変換]
        taxa-barplot.qzv    [系統組成の棒グラフ]

オプション:
  -e    conda環境変数パス         [default: \${HOME}/miniconda3/etc/profile.d/conda.sh ]
  -q    qiime2環境名             [default: qiime2-2021.8 ]
  -a    分類機(qza形式)           [sklearn使用時]
  -f    リファレンスfasta(qza形式) [blast使用時]
  -x    リファレンスfastaと対応する系統データ(qza形式) [blast使用時]
  -n    confidence              [default of qiime:0.7 ]
  -m    メタデータのファイル        [default: map.txt]
  -o    ASVテーブル(qza形式)   [default: taxonomy.qza]
  -O    ASVテーブル(tsv形式)   [default: taxonomy.tsv]
  -b    棒グラフの出力(qzv形式) [default: taxa-barplot.qzv]
  -c    CPU                  [default: 4]
  -h    ヘルプドキュメントの表示

EOS
}
## 1.2. 使用例の表示
function print_usg() {
cat << EOS
使用例:
    # sklearn
    $CMDNAME -a silva-138-99-nb-classifier.qza repset.qza table.qza

    # blast
    $CMDNAME -f silva-138-99-seqs.qza -x silva-138-99-tax.qza repset.qza table.qza

    # デフォルト設定とは異なる環境で実行する場合、conda環境変数のスクリプトと、qiime2の環境名を指定する
    CENV=/home/miniconda3/etc/profile.d/conda.sh
    Q2ENV=qiime2-2022.2
    $CMDNAME -a silva-138-99-nb-classifier.qza -e \${CENV} -q \${Q2ENV} repset.qza table.qza

EOS
}    
if [[ $# = 0 ]]; then print_doc; print_usg; exit 1; fi

# 2. オプション引数の処理
##  2.1. オプション引数の入力
while getopts a:f:x:e:q:n:m:o:b:O:h OPT
do
  case $OPT in
    "e" ) VALUE_e="$OPTARG";;
    "q" ) VALUE_q="$OPTARG";;
    "c" ) VALUE_c="$OPTARG";;
    "a" ) VALUE_a="$OPTARG";;
    "f" ) VALUE_f="$OPTARG";;
    "x" ) VALUE_x="$OPTARG";;
    "n" ) VALUE_n="$OPTARG";;
    "m" ) VALUE_m="$OPTARG";;
    "o" ) VALUE_o="$OPTARG";;
    "b" ) VALUE_b="$OPTARG";;
    "O" ) VALUE_O="$OPTARG";;
    "h" ) print_doc ; print_usg
            exit 1 ;;
    *) print_doc ; print_usg
        exit 1;;
    \? ) print_doc ; print_usg
            exit 1 ;;
  esac
done
shift `expr $OPTIND - 1`

## 2.2. オプション引数の判定及びデフォルト値
### 2.2.1. conda環境変数ファイルの存在確認
if [[ -z "$VALUE_e" ]]; then CENV="${HOME}/miniconda3/etc/profile.d/conda.sh"; else CENV=${VALUE_e}; fi
if [[ ! -f "${CENV}" ]]; then
 echo "[ERROR] The file for the conda environment variable cannot be found. ${CENV}"
 print_usg
 exit 1
fi

### 2.2.2. qiime2環境の存在確認
if [[ -z "$VALUE_q" ]]; then QENV="qiime2-2022.2"; else QENV=${VALUE_q}; fi
if conda info --envs | awk '!/^#/{print $1}'| grep -q "^${QENV}$" ; then
    :
else 
    echo "[ERROR] There is no ${QENV} environment."
    conda info --envs
    print_usg
    exit 1
fi

### 2.2.3. リファレンスファイル(classifier)を指定 fullpathの場合/Q2DBがある場合
if [[ -n "${Q2DB}" && -n "${VALUE_a}" && -z "${VALUE_f}" && -z "${VALUE_x}" ]] ; then
    CLF=$(dirname $Q2DB)/$(basename $Q2DB)/${VALUE_a}
elif [[ -z "${Q2DB}" && -n "${VALUE_a}" && -z "${VALUE_f}" && -z "${VALUE_x}" ]] ; then
    CLF="${VALUE_a}"
    echo -e "# ${CLF} was designated as the classifier."

elif [[ -n "${Q2DB}" && -z "${VALUE_a}" && -n "${VALUE_f}" && -n "${VALUE_x}" ]] ; then
    REFA=$(dirname $Q2DB)/$(basename $Q2DB)/${VALUE_f}
    RETAX=$(dirname $Q2DB)/$(basename $Q2DB)/${VALUE_x}
    echo -e "# ${REFA}  ${RETAX} were designated as the classifier."

elif [[ -z "${Q2DB}" && -z "${VALUE_a}" && -n "${VALUE_f}" && -n "${VALUE_x}" ]] ; then
    REFA="${VALUE_f}"
    RETAX="${VALUE_x}"
    echo -e "# ${REFA} ${RETAX} were designated as the classifier."
else
    echo -e "### [ERROR] Reference data not specified."
    echo -e "### It can be specified only by file name by setting the Q2DB environment variable."
    exit 1
fi

### 2.2.4. リファレンスファイル(fasta/taxonomy)存在確認 fullpathの場合/Q2DBがある場合
if [[ -e ${CLF} && ! -e ${REFA} && ! -e ${RETAX} ]] ; then
    echo "# ${CLF} was exists."
elif [[ ! -e ${CLF} && -e ${REFA} && -e ${RETAX} ]] ; then
    echo "# ${REFA} & ${RETAX} were exists."
else 
    echo -e "### [ERROR] The reference file not found. "
    echo -e "### Please specify classifier (qza format) or sequence/phylogenetic data (qza format) as reference data."
    echo -e "### The environment variable Q2DB can be set to specify the file name only."
    echo -e "### [e.g.]  export Q2DB=/root/ubuntu/db/qiime2 "
    if [[ -d ${Q2DB} ]] ; then echo -e "### The following files exist in ${Q2DB}."; ls -1 ${Q2DB}| grep "qza$" ; fi
    exit 1
fi
### 2.2.5. その他のオプション引数の判定
if [[ -z "$VALUE_n" ]]; then CONF=0.7; else CONF=${VALUE_n}; fi
if [[ -z "$VALUE_o" ]]; then OTAX=taxonomy.qza; else OTAX=${VALUE_o}; fi
if [[ -z "$VALUE_b" ]]; then OBP=taxa-barplot.qzv; else OBP=${VALUE_b}; fi
if [[ -z "$VALUE_O" ]]; then OTT=taxonomy.tsv; else OTT=${VALUE_O}; fi
if [[ -n "$VALUE_m" ]]; then META=${VALUE_m}; fi
if [[ -z "$VALUE_c" ]]; then NT=4; else NT=${VALUE_c};fi


# 3. コマンドライン引数の処理
if [[ $# = 2 && -f "$1" && -f "$2" ]]; then
    ASV=$1
    TAB=$2
else
    echo "### [ERROR] Two qza files are required as arguments. " 
    echo "### [ERROR] The first is the ASV and the second is the feature table. " 
    print_usg
    exit 1
fi


# 4. プログラムに渡す引数の一覧
cat << EOS >&2
### Taxonomy classification ###
conda environmental variables :     [ ${CENV} ]
qiime2 environment :                [ ${QENV} ]
number of threads :                 [ ${NT} ]  
The input ASV file path:            [ ${ASV} ] 
The input ASV table file path:      [ ${TAB} ]
Refference classifier for sklearn:  [ ${CLF} ]
confidence value for sklearn:       [ ${CONF} ]  
Refference fasta for blast :        [ ${REFA} ]
Refference taxonomy for blast:      [ ${RETAX} ]
metadata for drawing bar-plot       [ ${META} ]
output taxonomy:                    [ ${OTAX} ]  
output taxonomy table:              [ ${OTT} ]
output barplot:                     [ ${OBP} ]

EOS


# 5. メイン
## 5.1. qiime2 起動
source ${CENV}
if echo ${CENV} | grep -q "anaconda" ; then source activate ${QENV}; else conda activate ${QENV}; fi

## 5.2. qiime feature-lassifierを実行
### taxonomy.qza が存在していれば、exit
if [[ -f ${OTAX} ]] ; then echo "[ERROR] The ${OTAX} was aleady exist."; exit 1; fi

if [[ -f ${CLF} && ! -f ${REFA} && ! -f ${RETAX} ]]; then
    echo "### Execute qiime feature-classifier classify-sklearn"
    qiime feature-classifier classify-sklearn \
    --i-classifier ${CLF} \
    --i-reads ${ASV} \
    --p-confidence ${CONF} \
    --o-classification ${OTAX} \
    --p-n-jobs ${NT}

elif [[ -f ${REFA} && -f ${RETAX} && ! -f ${CLF} ]]; then
    echo "### Execute qiime feature-classifier classify-consensus-blast"
    # blast
    qiime feature-classifier classify-consensus-blast \
    --i-query ${ASV} \
    --i-reference-reads ${REFA} \
    --i-reference-taxonomy ${RETAX} \
    --o-classification ${OTAX} 

else 
    echo "[ERROR] 参照データがみつかりません。参照データとして分類機もしくは配列と系統データを指定します。"
    echo "環境変数Q2DBを設定することでファイル名だけで指定可能です。"
    echo "[e.g.] export Q2DB=/root/ubuntu/db/qiime2 "
    exit 1
fi

### taxonomy.qza ができなければexit
if [[ ! -f ${OTAX} ]] ; then echo "[ERROR] The ${OTAX} was not output."; exit 1; fi

## 5.3. taxonomyテーブルをqzv形式とテキストファイルに変換
### 出力ディレクトリを確認
OUTDZ='exported_qzv'
if [[ -d "${OUTDZ}" ]]; then
    echo "[WARNING] ${OUTDZ} was already exists. The output files may be overwritten." >&2
else 
    mkdir "${OUTDZ}"
fi

OUTD='exported_txt'; 
if [[ -d "${OUTD}" ]];then
    echo "[WARNING] ${OUTD} already exists. The output files may be overwritten." >&2
else 
    mkdir "${OUTD}"
fi

### taxonomyテーブルをtsv形式に変換
unzip -qq ${OTAX} -d tmp 
mv tmp/*/data/taxonomy.tsv ./${OUTD}
rm -r ./tmp

### taxonomyテーブルをqzv形式に変換
qiime metadata tabulate \
--m-input-file ${OTAX} \
--o-visualization ./${OUTDZ}/${OTAX%.*}.qzv

## 5.4. 棒グラフを作成　qiime taxa barplot
TAB=table.qza; OTAX=taxonomy.qza;
if [[ -f ${TAB} && -f ${OTAX} && -f ${META} ]]; then
    qiime taxa barplot \
    --i-table ${TAB} \
    --i-taxonomy ${OTAX} \
    --m-metadata-file ${META} \
    --o-visualization ${OUTDZ}/${OBP}

elif [[ -f ${TAB} && -f ${OTAX} && ! -f ${META} ]] ; then
    echo '[WARNING] A meta-data file was not specified, bar-plot was created without meta-data .' >&2
    qiime taxa barplot \
    --i-table ${TAB} \
    --i-taxonomy ${OTAX} \
    --o-visualization ${OUTDZ}/${OBP}
else
    echo "[ERROR] ${TAB}, ${OTAX} : One of these is missing."
    exit 1
fi
