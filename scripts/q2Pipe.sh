#!/bin/bash
VERSION=0.1.230527
AUTHOR=SHOGO_KONISHI
CMDNAME=`basename $0`


### Contents  ###
# 1. ドキュメント
#  1.1. ヘルプの表示 
#  1.2. 使用例の表示
# 2. オプション引数の処理
# 3. コマンドライン引数の処理
# 4. プログラムに渡す引数の一覧 
# 5. qiime2パイプライン実行 
#  5-1. マニフエストファイル作成(q2Manif.sh) & デノイジング(q2Denoise.sh)
#  5-2. 系統推定実行(q2Classify.sh)
#  5-3. 系統組成表作成, 代表配列系統樹作成(q2Merge.sh) 
###

# 1. ドキュメント
#  1.1. ヘルプの表示
function print_doc() {
cat << EOS
使用法:
    $CMDNAME [オプション] ./fastq_dir
   
説明:
  q2Manif.sh    マニフェストファイル作成
  q2Denoise.sh  fastqファイルのインポートとデノイジング
  q2Classify.sh 系統推定 (sk-learn/blast)
  q2Merge.sh    系統組成表(taxonomyランク毎)を作成
  q2Tree.sh     系統樹作成

オプション: 
  -e    conda環境変数パス[default: \${HOME}/miniconda3/etc/profile.d/conda.sh ]
  -q    qiime2環境名[default: qiime2-2021.8 ]
  -s    シングルエンド
  -p    ペアエンド
  -F    Read1 で切り捨てる位置[default: 270]
  -R    Read2 で切り捨てる位置[default: 200]
  -a    分類機(qza形式) [sklearn使用時]
  -f    リファレンスfasta(qza形式) [blast使用時]
  -x    リファレンスfastaと対応する系統データ(qza形式) [blast使用時]
  -m    メタデータのファイル  
  -h    ヘルプドキュメントの表示

EOS
}
#  1.2. 使用例の表示
function print_usg () {
cat << EOS
使用例: 
  # All default setting
  $CMDNAME ./fastq_dir

  # Change environment, and single-end setting
  CENV="\${HOME}/miniconda3/etc/profile.d/conda.sh"
  QENV='qiime2-2022.2'
  REF="\${HOME}/qiime2/silva-138-99-nb-classifier.qza"
  $CMDNAME -e \${CENV} -q \${QENV} -a \${REF} -s ./fastq_dir 

  # paired-end trunc length setting, meta-data file indicating 
  $CMDNAME -e \${CENV} -q \${QENV} -a \${REF} -F 270 -R 210 -m map.txt -p ./fastq_dir

EOS
}

# 2. オプション引数の処理
#  2.1. オプション引数の入力
while getopts e:q:spF:R:a:f:x:m:h OPT
do
  case $OPT in
    "e" ) CENV="$OPTARG";;
    "q" ) QENV="$OPTARG";;
    "s" ) FLG_s="TRUE" ;;
    "p" ) FLG_p="TRUE" ;;
    "F" ) VALUE_F="$OPTARG";;
    "R" ) VALUE_R="$OPTARG";;
    "a" ) VALUE_a="$OPTARG";;
    "f" ) VALUE_f="$OPTARG";;
    "x" ) VALUE_x="$OPTARG";;
    "m" ) VALUE_m="$OPTARG";;
    "h" ) print_doc
            exit 1 ;; 
    *) print_doc
        exit 1;; 
     \? ) print_doc
            exit 1 ;;
  esac
done
shift `expr $OPTIND - 1`

#  2.2. オプション引数の判定およびデフォルト値の指定
if [[ -z "$CENV" ]]; then CENV="${HOME}/miniconda3/etc/profile.d/conda.sh"; fi
if [[ -z "$QENV" ]]; then QENV="qiime2-2022.2"; fi

## conda環境変数ファイルの存在確認, qiime2環境の存在確認
if [[ ! -e "${CENV}" ]]; then
 echo "[ERROR] The file for the conda environment variable cannot be found. ${CENV}"
 print_usg
 exit 1
fi 
conda info --envs | awk '!/^#/{print $1}'| grep -q "^${QENV}$" || { echo "[ERROR] There is no ${QENV} environment." ; conda info --envs ; print_usg; exit 1 ; } 

## リファレンスファイルの判定
if [[ -n "${Q2DB}" && -n "${VALUE_a}" && -z "${VALUE_f}" && -z "${VALUE_x}" ]] ; then
    CLF=$(dirname $Q2DB)/$(basename $Q2DB)/${VALUE_a}
    echo -e "# ${CLF} was designated as the classifier." 
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

## その他オプション引数の判定
if [[ "${FLG_s}" == "TRUE" && "${FLG_p}" != "TRUE" ]]; then 
    DRCTN="single"
elif [[ "${FLG_s}" != "TRUE" && "${FLG_p}" == "TRUE" ]]; then
    DRCTN="paired"
    if [[ -z "${VALUE_F}" || -z "${VALUE_R}" ]]; then
        TRUNKF=270; TRUNKR=200
    elif [[ -n "${VALUE_F}" && -n "${VALUE_R}" ]]; then 
        TRUNKF=${VALUE_F}; TRUNKR=${VALUE_R}
    else 
        echo -e "[ERROR]"
        exit 1
    fi
else 
    echo "[ERROR] The optin flag [-s|-p] as single or paired end,  must be set."
    exit 1
fi
if [[ -n "$VALUE_m" ]]; then META=${VALUE_m}; fi

# 3. コマンドライン引数の処理
if [[ $# = 1 && -d $1 ]]; then
    FQD=`basename $1`
    CPFQD=$(cd $(dirname $1) && pwd)/${FQD}
else
    echo "[ERROR] Either the directory is not specified or the directory cannot be found." >&2
    print_usg
    exit 1
fi

# 4. プログラムに渡す引数の一覧
cat << EOS >&2
### Arguments for this pipe-line ###
 conda environmental variables :         [ ${CENV} ]
 qiime2 environment :                    [ ${QENV} ] 

 paired/single end :                     [ ${DRCTN} ]
 The position to be truncated at Read1:  [ ${TRUNKF} ]
 The position to be truncated at Read2:  [ ${TRUNKR} ]

 Refference classifier for sklearn:  [ ${CLF} ]
 Refference fasta for blast :        [ ${REFA} ]
 Refference taxonomy for blast:      [ ${RETAX} ]
 metadata for drawing bar-plot       [ ${META} ]

EOS

# 5. qiime2パイプライン実行
# 5-1. マニフエストファイル作成(q2Manif.sh) & デノイジング(q2Denoise.sh)
if [[ "${DRCTN}" = "single" ]]; then
  q2Manif.sh -s ${CPFQD}
  q2Denoise.sh -e ${CENV} -q ${QENV} -s manifest.txt

elif [[ "${DRCTN}" = "paired" ]]; then
  q2Manif.sh -p ${CPFQD}
  q2Denoise.sh -e ${CENV} -q ${QENV} -F ${TRUNKF} -R ${TRUNKR} -p manifest.txt
fi
# catch error

# 5-2. 系統推定実行(q2Classify.sh)
if [[ -e ${CLF} && ! -e ${REFA} && ! -e ${RETAX} ]] ; then
  echo "# classify-sklearn  was execute."
  if [[ -f ${META} ]] ; then
    q2Classify.sh -e ${CENV} -q ${QENV} -a ${CLF} -m ${META} repset.qza table.qza
  else
    q2Classify.sh -e ${CENV} -q ${QENV} -a ${CLF} repset.qza table.qza
  fi

elif [[ ! -e ${CLF} && -e ${REFA} && -e ${RETAX} ]] ; then
  echo "# classify-consensus-blast was execute."
  if [[ -f ${META} ]] ; then
    q2Classify.sh -e ${CENV} -q ${QENV} -f ${REFA} -x ${RETAX}  -m ${META} repset.qza table.qza
  else
    q2Classify.sh -e ${CENV} -q ${QENV} -f ${REFA} -x ${RETAX} repset.qza table.qza 
  fi

else 
    echo "[ERROR] Reference data cannot be found. "
    exit 1
fi
# catch error

# 5-3. 系統組成表作成(q2Merge.sh) 
q2Merge.sh -e ${CENV} -q ${QENV} -t table.qza -s repset.qza taxonomy.qza

# 5-4. 代表配列系統樹作成(q2Tree.sh)
q2Tree.sh -e ${CENV} -q ${QENV} -s repset.qza taxonomy.qza