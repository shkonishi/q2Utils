#!/bin/bash
VERSION=0.0.230224
AUTHOR=SHOGO_KONISHI
CMDNAME=`basename $0`

# ヘルプの表示
function print_doc() {
cat << EOS
使用法:
    $CMDNAME [オプション] ./fastq_dir
   
説明:
  q2Manif.sh    マニフェストファイル作成
  q2Denoise.sh  fastqファイルのインポートとデノイジング
  q2Classify.sh 系統推定 (sk-learn/blast)
  q2Merge.sh    系統組成表と系統樹作成

  output file names

オプション: 
  -e    conda環境変数パス[default: \${HOME}/miniconda3/etc/profile.d/conda.sh ]
  -q    qiime2環境名[default: qiime2-2021.8 ]
  -s|-p シングルエンドまたはペアエンド
  -F    Read1 で切り捨てる位置[default: 280]
  -R    Read2 で切り捨てる位置[default: 210]
  -a    分類機(qza形式) [sklearn使用時]
  -f    リファレンスfasta(qza形式) [blast使用時]
  -x    リファレンスfastaと対応する系統データ(qza形式) [blast使用時]
  -m    メタデータのファイル  
  -h    ヘルプドキュメントの表示

  qiime dada2 denoise-pairedにおけるオプション[--p-trunc-len-f/--p-trunc-len-r]に与える値

EOS
}

function print_usg () {
cat << EOS
使用例: 
  # All default settings
  $CMDNAME ./fastq_dir

  # Change environment 
  CENV='\${HOME}/miniconda3/etc/profile.d/conda.sh'
  QENV='qiime2-2022.2'
  CLSF='\${HOME}/qiime2/silva-138-99-nb-classifier.qza'
  $CMDNAME -e \${CENV} -q \${QENV} -a \${CLSF} ./fastq_dir 

EOS
}


### 引数チェック ###
# 1-1. オプション引数の入力処理 
# 1-2. conda環境変数ファイルの存在確認
# 1-3. qiime2環境の存在確認
# 1-4. コマンドライン引数の判定 
# 1-5. オプション引数の判定
# 1-6. プログラムに渡す引数の一覧
###

# 1-1. オプション引数の入力処理
while getopts e:q:spF:R:a:f:x:m:h OPT
do
  case $OPT in
    "e" ) VALUE_e="$OPTARG";;
    "q" ) VALUE_q="$OPTARG";;
    "s" ) FLG_s="TRUE" ;;
    "p" ) FLG_p="TRUE" ;;
    "F" ) VALUE_F="$OPTARG";;
    "R" ) VALUE_R="$OPTARG";;
    "a" ) VALUE_a="$OPTARG";;
    "f" ) VALUE_f="$OPTARG";;
    "x" ) VALUE_x="$OPTARG";; 
    "h" ) print_doc
            exit 1 ;; 
    *) print_doc
        exit 1;; 
     \? ) print_doc
            exit 1 ;;
  esac
done
shift `expr $OPTIND - 1`


# 1-2. conda環境変数ファイルの存在確認
if [[ -z "$VALUE_e" ]]; then CENV="${HOME}/miniconda3/etc/profile.d/conda.sh"; else CENV=${VALUE_e}; fi
if [[ -f "${CENV}" ]]; then : ; else echo "[ERROR] The file for the conda environment variable cannot be found. ${CENV}"; exit 1; fi

# 1-3. qiime2環境の存在確認
if [[ -z "$VALUE_q" ]]; then QENV="qiime2-2022.2"; else QENV=${VALUE_q}; fi
if conda info --envs | awk '!/^#/{print $1}'| grep -qx "^${QENV}$" ; then
    :
else 
    echo "[ERROR] There is no ${QENV} environment."
    conda info --envs
    exit 1
fi

# 1-4. コマンドライン引数の判定 
if [[ $# = 1 && -d $1 ]]; then
    FQD=`basename $1`
else
    echo "[ERROR] Either the directory is not specified or the directory cannot be found." >&2
    print_usg
    exit 1
fi

# 1-5. オプション引数の判定
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
    echo "[ERROR] The optin flag [-s|-p] must be set."
    exit 1
fi

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
if [[ -n "$VALUE_m" ]]; then META=${VALUE_m}; fi



# 1-6. プログラムに渡す引数の一覧
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

######
EOS

### MAIN ###
# 2-1. q2Manif.sh & q2Denoise.sh 実行: マニフェストファイル作成, fastqインポート, dada2によるdenoising
# 2-2. q2Classify.sh実行: 系統推定
# 2-3. q2Merge.sh実行: 系統組成表作成, 代表配列系統樹作成, 
###

# 2-1. Create a manifest file  Date import and Denoising  --p-trunc-len-f
if [[ "${DRCTN}" == "single" ]]; then
  q2Manif.sh -s ${FQD}
  q2Denoise.sh -e ${CENV} -q ${QENV} -s manifest.txt

elif [[ "${DRCTN}" == "paired" ]]; then
  q2Manif.sh -p ${FQD}
  q2Denoise.sh -e ${CENV} -q ${QENV} -p -F ${TRUNKF} -R ${TRUNKR} manifest.txt
fi

# exit

# 2-2. Classification
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

# exit

# 2-3. merge & tree
q2Merge.sh -e ${CENV} -q ${QENV} -t table.qza -s repset.qza -u taxonomy.qza
