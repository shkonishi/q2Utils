#!/bin/bash
VERSION=0.0.231124
AUTHOR=SHOGO_KONISHI
CMDNAME=$(basename $0)

### <CONTENTS> qiime feature-classifierを用いて系統推定 ###
# 1. ドキュメント
# 2. オプション引数の処理
#  2.1. オプション引数の入力
#  2.2. オプション引数の判定
# 3. コマンドライン引数の処理
# 4. 引数の一覧
# 5. qiime2パイプライン実行
#  5.1. qiime2 起動
#  5.2. qiime feature-lassifierを実行
#  5.3. taxonomyテーブルをqzv形式とテキストファイルに変換
#  5.4. 棒グラフを作成　qiime taxa barplot
###

# 1. ドキュメント
## 1.1. ヘルプの表示
function print_doc() {
cat << EOS
使用法:
    $CMDNAME [オプション] <repset.qza> <table.qza>

用語の定義およびこのプログラム中で使用されるデフォルトファイル名:
    ASV                 Denoisingされた配列. dada2の出力 [repset.qza]
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
  -e    conda環境変数パス                               [default: \${HOME}/miniconda3/etc/profile.d/conda.sh ]
  -q    qiime2環境名                                    [default: qiime2-2021.8 ]
  -a    分類機(qza形式)                                 [sklearn使用時]
  -f    リファレンスfasta(qza形式)                      [blast使用時]
  -x    リファレンスfastaと対応する系統データ(qza形式)  [blast使用時]
  -n    confidence                                      [default of qiime:0.7 ]
  -m    メタデータのファイル
  -o    ASVテーブル(qza形式)                            [default: taxonomy.qza]
  -O    ASVテーブル(tsv形式)                            [default: taxonomy.tsv]
  -b    棒グラフの出力(qzv形式)                         [default: taxa-barplot.qzv]
  -c    CPU                                             [default: 4]
  -h    ヘルプドキュメントの表示

使用例:
    # sklearn
    $CMDNAME -a silva-138-99-nb-classifier.qza repset.qza table.qza

    # blast
    $CMDNAME -f silva-138-99-seqs.qza -x silva-138-99-tax.qza repset.qza table.qza

    # デフォルト設定とは異なる環境で実行する場合、conda環境変数のスクリプトと、qiime2の環境名を指定する
    CENV=/home/miniconda3/etc/profile.d/conda.sh
    Q2ENV=qiime2-2022.2
    $CMDNAME -e \${CENV} -q \${Q2ENV} -a silva-138-99-nb-classifier.qza repset.qza table.qza

EOS
}
if [[ $# = 0 ]]; then print_doc; exit 1; fi

# 2. オプション引数の処理
##  2.1. オプション引数の入力
while getopts e:q:c:a:f:x:n:m:o:b:O:h OPT
do
  case $OPT in
    "e" ) CENV="$OPTARG";;
    "q" ) QENV="$OPTARG";;
    "c" ) NT="$OPTARG";;
    "a" ) VALUE_a="$OPTARG";;
    "f" ) VALUE_f="$OPTARG";;
    "x" ) VALUE_x="$OPTARG";;
    "n" ) CONF="$OPTARG";;
    "m" ) META="$OPTARG";;
    "o" ) OTAX="$OPTARG";;
    "b" ) OBP="$OPTARG";;
    "O" ) OTT="$OPTARG";;
    "h" ) print_doc ; exit 1 ;;
    *) print_doc ; exit 1;;
    \? ) print_doc ; exit 1 ;;
  esac
done
shift $(expr $OPTIND - 1)

## 2.2. オプション引数の判定及びデフォルト値
### 2.2.1. conda環境変数ファイルの存在確認
if [[ -z "$CENV" ]]; then CENV="${HOME}/miniconda3/etc/profile.d/conda.sh"; fi
if [[ ! -f "${CENV}" ]]; then
 echo "[ERROR] The file for the conda environment variable cannot be found. ${CENV}" >&2 ; exit 1
fi

### 2.2.2. qiime2環境の存在確認
if [[ -z "$QENV" ]]; then QENV='qiime2-2022.2'; fi
conda info --env | grep -q $QENV || { echo "[ERROR] There is no ${QENV} environment."  >&2 ; conda info --envs >&2 ; exit 1 ; }

### 2.2.3. リファレンスファイル(classifier)を指定 fullpathの場合/Q2DBがある場合
if [[ -n "${Q2DB}" && -n "${VALUE_a}" && -z "${VALUE_f}" && -z "${VALUE_x}" ]] ; then
    CLF=$(dirname $Q2DB)/$(basename $Q2DB)/${VALUE_a}
elif [[ -z "${Q2DB}" && -n "${VALUE_a}" && -z "${VALUE_f}" && -z "${VALUE_x}" ]] ; then
    CLF="${VALUE_a}"
    echo -e "[INFO] ${CLF} was designated as the classifier."

elif [[ -n "${Q2DB}" && -z "${VALUE_a}" && -n "${VALUE_f}" && -n "${VALUE_x}" ]] ; then
    REFA=$(dirname $Q2DB)/$(basename $Q2DB)/${VALUE_f}
    RETAX=$(dirname $Q2DB)/$(basename $Q2DB)/${VALUE_x}
    echo -e "[INFO] ${REFA} ${RETAX} were designated as the classifier."

elif [[ -z "${Q2DB}" && -z "${VALUE_a}" && -n "${VALUE_f}" && -n "${VALUE_x}" ]] ; then
    REFA="${VALUE_f}"
    RETAX="${VALUE_x}"
    echo -e "[INFO] ${REFA} ${RETAX} were designated as the classifier."
else
    echo -e "[ERROR] Reference data not specified."
    echo -e "[ERROR] It can be specified only by file name by setting the Q2DB environment variable."
    exit 1
fi

### 2.2.4. リファレンスファイル(fasta/taxonomy)存在確認 fullpathの場合/Q2DBがある場合
if [[ -e ${CLF} && ! -e ${REFA} && ! -e ${RETAX} ]] ; then
    echo "[INFO] ${CLF} was exists."
elif [[ ! -e ${CLF} && -e ${REFA} && -e ${RETAX} ]] ; then
    echo "[INFO] ${REFA} & ${RETAX} were exists."
else
    echo -e "[ERROR] The reference file not found. "
    echo -e "Please specify classifier (qza format) or sequence/taxonomy data (qza format) as reference data."
    echo -e "The environment variable Q2DB can be set to specify the file name only."
    echo -e "[e.g.]  export Q2DB=/home/db/qiime2_db "
    if [[ -d ${Q2DB} ]] ; then echo -e "### The following files exist in ${Q2DB}."; ls -1 ${Q2DB}| grep "qza$" ; fi
    exit 1
fi

### 2.2.5. その他のオプション引数の判定
if [[ -z "$CONF" ]]; then CONF=0.7 ; fi
if [[ -z "$OTAX" ]]; then OTAX='taxonomy.qza' ; fi
if [[ -f "$OTAX" ]] ; then echo "[ERROR] The ${OTAX} was aleady exist." >&2 ; exit 1; fi
if [[ -z "$OBP" ]]; then OBP='taxa-barplot.qzv' ; fi
if [[ -z "$OTT" ]]; then OTT='taxonomy.tsv' ; fi
if [[ -z "$META" ]]; then META='map.txt' ; fi
if [[ -z "$NT" ]]; then NT=4 ; fi
OUTDZ='exported_qzv'
if [[ -d "${OUTDZ}" ]]; then echo "[WARNING] ${OUTDZ} was already exists. The output files may be overwritten." >&2 ; fi
OUTD='exported_txt'; 
if [[ -d "${OUTD}" ]];then echo "[WARNING] ${OUTD} already exists. The output files may be overwritten." >&2 ; fi

# 3. コマンドライン引数の処理
if [[ $# = 2 && -f "$1" && -f "$2" ]]; then
    ASV=$1
    TAB=$2
else
    echo "[ERROR] Two qza files are required as arguments. " >&2
    echo "[ERROR] The first is the ASV and the second is the feature table. " >&2
    exit 1
fi

# 4. プログラムに渡す引数の一覧
cat << EOS >&2

### Taxonomy classification ###
conda environmental variables       [ ${CENV} ]
qiime2 environment                  [ ${QENV} ]
number of threads                   [ ${NT} ]
The input ASV file path             [ ${ASV} ]
The input ASV table file path       [ ${TAB} ]
Refference classifier for sklearn   [ ${CLF} ]
confidence value for sklearn        [ ${CONF} ]
Refference fasta for blast          [ ${REFA} ]
Refference taxonomy for blast       [ ${RETAX} ]
metadata for drawing bar-plot       [ ${META} ]
output taxonomy                     [ ${OTAX} ]
output taxonomy table               [ ${OUTD}/${OTT} ]
output barplot                      [ ${OUTDZ}/${OBP} ]

EOS


# 5. qiime2パイプライン実行 
## 5.1. qiime2 起動
source ${CENV}
if echo ${CENV} | grep -q "anaconda" ; then source activate ${QENV}; else conda activate ${QENV}; fi

## 5.2. qiime feature-classifierを実行
if [[ -f ${CLF} && ! -f ${REFA} && ! -f ${RETAX} ]]; then
    echo "# [CMND] Execute qiime feature-classifier classify-sklearn" >&2
    cmd1="qiime feature-classifier classify-sklearn --i-classifier ${CLF} --i-reads ${ASV} --p-confidence ${CONF} --o-classification ${OTAX} --p-n-jobs ${NT}"
    echo ${cmd1} >&2 ; eval ${cmd1}

elif [[ -f ${REFA} && -f ${RETAX} && ! -f ${CLF} ]]; then
    echo "# [CMND] Execute qiime feature-classifier classify-consensus-blast" >&2
    cmd1="qiime feature-classifier classify-consensus-blast --i-query ${ASV} --i-reference-reads ${REFA} --i-reference-taxonomy ${RETAX} --o-classification ${OTAX}" 
    echo ${cmd1} >&2 ; eval ${cmd1}

else
    echo "[ERROR] 参照データがみつかりません。参照データとして分類機もしくは配列と系統データを指定します。" >&2
    echo " 環境変数Q2DBを設定することでファイル名だけで指定可能です。" >&2
    echo " [e.g.] export Q2DB=/home/user/db/qiime2 " >&2
    exit 1
fi

### taxonomy.qza ができなければexit
if [[ ! -f ${OTAX} ]] ; then echo "[ERROR] The ${OTAX} was not output." >&2 ; exit 1; fi

## 5.3. taxonomyテーブルをqzv形式とテキストファイルに変換
### 出力ディレクトリを確認
if [[ ! -d "${OUTDZ}" ]]; then mkdir "${OUTDZ}" ; fi
if [[ ! -d "${OUTD}" ]]; then mkdir "${OUTD}" ; fi

### taxonomyテーブルをtsv形式に変換
unzip -qq ${OTAX} -d tmp 
mv tmp/*/data/taxonomy.tsv ./${OUTD}
rm -r ./tmp

### taxonomyテーブルをqzv形式に変換
echo "# [CMND] Convert taxonomy to qzv file" >&2
cmd2="qiime metadata tabulate --m-input-file ${OTAX} --o-visualization ./${OUTDZ}/${OTAX%.*}.qzv"
echo ${cmd2} >&2 ; eval ${cmd2}

## 5.4. 棒グラフを作成　qiime taxa barplot
if [[ -f ${TAB} && -f ${OTAX} && -f ${META} ]]; then
    echo "# [CMND] Create taxonomy barplot with metadata" >&2
    cmd3="qiime taxa barplot --i-table ${TAB} --i-taxonomy ${OTAX} --m-metadata-file ${META} --o-visualization ${OUTDZ}/${OBP}"
    echo ${cmd3} >&2 ; eval ${cmd3}

elif [[ -f ${TAB} && -f ${OTAX} && ! -f ${META} ]] ; then
    echo "# [CMND] Create taxonomy barplot" >&2
    cmd3="qiime taxa barplot --i-table ${TAB} --i-taxonomy ${OTAX} --o-visualization ${OUTDZ}/${OBP}"
    echo ${cmd3} >&2 ; eval ${cmd3}
else
    echo "[ERROR] ${TAB}, ${OTAX} : One of these is missing." >&2
    exit 1
fi

exit 0
