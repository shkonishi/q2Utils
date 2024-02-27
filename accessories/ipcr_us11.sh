#!/bin/bash
VERSION=0.0.240226
AUTHOR=SHOGO_KONISHI
CMDNAME=$(basename $0)

### <CONTENTS> usearchを用いてin-silico pcr ###
# 1. ドキュメント
# 2. オプション引数の処理
#  2.1. オプション引数の入力
#  2.2. オプション引数の判定
# 3. コマンドライン引数の処理
# 4. 引数の一覧
# 5. メインルーチン実行
#  5.1. 関数定義
#  5.2. cutadaptを実行
#  5.3. fastq-joinを実行
###

# 1. Documents
## 1.1. Help
function print_doc (){
cat <<EOS >&2
要件
  usearch ver.11

使用法:
  $CMDNAME [オプション] <fasta_dir>
  $CMDNAME [オプション] <fasta>

オプション:
  -p    プライマーファイル[default: primers.txt]
  -r    リージョン選択 [e.g. : v3v4]
  -s    fastaファイルのサフィックス[default: fna]

  usearch search_pcr2 のオプション
  -m    最小配列長 [default: 100]
  -M    最大配列長 [default: 500]
  -d    最大ミスマッチ [default: 2]

使用例:
  # fastaのディレクトリ指定(primer.txtはスクリプトと同じ場所においておけば、省略可)
  ${CMDNAME} -p primers.txt -r v3v4 ./fasta_dir
  # fastaファイル1つのみ、プライマー配列直接指定
  ${CMDNAME} -F ATGATGC -R TAGCAT -m 100 -M 500 -d 2 template.fasta

EOS
}

if [[ "$#" == 0 ]]; then print_doc ; exit 1 ; fi

## 1.2. Error or Log
#function print_err() { echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]:$*" >&2 ; exit 1 ; }
#function print_log() { echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]:$*" >&2 ; }

# 2. Check arguments
## 2.1. オプション引数の入力
while getopts p:r:s:F:R:m:M:d:h OPT
do
  case $OPT in
    "p" ) PRM="$OPTARG" ;;
    "r" ) REGION="$OPTARG" ;;
    "s" ) SFX="$OPTARG" ;;
    "F" ) FP="$OPTARG" ;;
    "R" ) RP="$OPTARG" ;;
    "m" ) MN="$OPTARG" ;;
    "M" ) MX="$OPTARG" ;; 
    "d" ) DIF="$OPTARG";;
    "h" ) print_doc ; exit 1 ;; 
     \? ) print_doc ; exit 1 ;;
  esac
done
shift $(expr $OPTIND - 1)

## 2.2. オプション引数のチェック及びデフォルト値の指定
if [[ -z "${PRM}" ]]; then PRM="$(dirname $0)/primers.txt" ; fi
if [[ ! -f "${PRM}" && -z "${FP}" && -z "${RP}" ]]; then 
  echo "[ERROR] '$PRM' does not exist. Also $FP and $RP are not specified" ; exit 1
elif [[ -f "${PRM}" && -z "${FP}" && -z "${RP}" ]]; then  
  if [[ -z "$REGION" ]]; then echo "[ERROR] Region name must be set with '-r' option." ; exit 1; fi
  FP=$(cat ${PRM} | awk -F"[\x20\t]+" -v REGION="${REGION}" '$1==REGION{print $2}')
  RP=$(cat ${PRM} | awk -F"[\x20\t]+" -v REGION="${REGION}" '$1==REGION{print $3}')
  if [[ $FP == "" || $RP == "" ]]; then echo "[ERROR] You should select as follows."; cat ${PRM}; echo; exit 1 ;fi
elif [[ -n "${FP}" && -n "${RP}" ]]; then
  unset PRM REGION
fi
if [[ -z "$SFX" ]]; then SFX='fna'; fi
if [[ -z "${MN}" ]]; then MN='100' ; fi
if [[ -z "${MX}" ]]; then MX='500' ; fi
if [[ -z "${DIF}" ]]; then DIF='2' ; fi

## 2.3. Command line arguments
if [[ $# = 1 && -f "$1" ]]; then
  QUERY=$1 
elif [[ $# = 1 && -d "$1" ]]; then
  FAD=$1
  ls ${FAD}/*.${SFX} > /dev/null 2>&1 || { echo "[ERROR] No fasta file found in ${FAD} [e.g.  .${SFX} ] " >&2 ; exit 1; }
else
  echo "[ERROR] Could not find fasta" >&2 ; exit 1
fi


## 2.4 Requirement existence
if ! command -v usearch11 &> /dev/null; then echo "[ERROR] Could not find usearh" ; exit 1 ; fi


# 3. Print arguments
cat << EOS >&2
### Arguments ###
Input             [ ${QUERY} ] 
Input dir.        [ ${FAD} ]
Primer file       [ ${PRM} ]
Region name       [ ${REGION} ]
Forward primer    [ ${FP} ]
Reverse primer    [ ${RP} ]
Min length        [ ${MN} ]
Max length        [ ${MX} ]
Max diffs         [ ${DIF} ]

EOS
# 5. Main
## 5.1. Functions
# NO FUNCTIONS

## 5.2. Main routine
if [[ ${QUERY} != "" ]]; then
  SFX=${QUERY##*.}
  PFX1=$(basename ${QUERY} | sed -e "s/\.${SFX}//" )
  if [[ ${REGION} != "" ]] ; then PFX="${PFX1}_${REGION}" ; else PFX="${PFX1}_pcr" ; fi
  cmd="usearch11 -search_pcr2 ${QUERY} -fwdprimer ${FP} -revprimer ${RP} -minamp ${MN} -maxamp ${MX} -maxdiffs ${DIF} -strand both -fastaout ${PFX}.fa -tabbedout ${PFX}.tab"
  echo "[CMD] $cmd"
  eval $cmd
elif [[ ${FAD} != "" ]]; then 
  for i in ${FAD}/*.${SFX}; do 
    SFX=${i##*.}
    PFX1=$(basename ${i} | sed -e "s/\.${SFX}//" )
    if [[ ${REGION} != "" ]] ; then PFX="${PFX1}_${REGION}" ; else PFX="${PFX1}_pcr" ; fi
    cmd="usearch11 -search_pcr2 ${i} -fwdprimer ${FP} -revprimer ${RP} -minamp ${MN} -maxamp ${MX} -maxdiffs ${DIF} -strand both -fastaout ${PFX}.fa -tabbedout ${PFX}.tab"
    echo "[CMD] $cmd"
    eval $cmd
  done
fi


exit 0
