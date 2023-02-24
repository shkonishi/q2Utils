#!/bin/bash
VERSION=0.1.230217
AUTHOR=SHOGO_KONISHI
CMDNAME=`basename $0`

# ヘルプの表示
function print_doc() {
cat << EOS
使用法:
    $CMDNAME [options] <fastq_directory>

説明:
    このスクリプトは、qiime2でfastqデータインポートする際に用いるマニフェストファイルを作成します。
    デフォルトではCSV形式のファイルを作成します。
    TSVファイルを使用する場合、'qiime tools import' のオプションを以下のように指定する必要があります。
    [ --input-format SingleEndFastqManifestPhred33V2 ]
    
    fastqファイルは、以下の拡張子[*.fastq | *.fq | *.fastq.gz | *.fq.gz] で判定されます。
    また、read1またはread2は、ファイル名に含まれる以下の文字列で判定されます。[_R1|_R2] もしくは　[_1 |_2].
    [_1|_2]の場合、例えば<_1.fastq.gz> <_1.qc.fastq.gz>のように直後に.拡張子が続く必要があります。

    # Note: R2ファイルがなくても-pをつけるとペアエンドのmanifestを作ってしまう。-> ファイルの存在確認
    # Note: R2ファイルがあっても-sで実行するとペアの配列を別々の配列と判定されてしまう。
    

オプション:
  -s  single end
  -p  paired-end
  -d  delimitter[default: , ]
  -o  出力ファイル名 [default: manifest.csv]
  -h  ヘルプドキュメントの表示

EOS
}
# 使用法の表示
function print_usg(){
cat << EOS
Examples:
    $CMDNAME -s fqdir    [single-end]
    $CMDNAME -p fqdir    [paired-end]
    $CMDNAME -s -d "\t" -o manifest.tsv fqdir [TSV file output] 
EOS
}

### 引数チェック ###
# 1-1. オプションの処理
# 1-2. コマンドライン引数の判定
# 1-3. オプション引数の判定
# 1-4. プログラムに渡す引数の一覧
###

# 1-1. オプションの処理
while getopts spo:d:h OPT
do
  case $OPT in
    "s" ) FLG_s="TRUE" ;;
    "p" ) FLG_p="TRUE" ;;
    "d" ) VALUE_d="$OPTARG" ;;
    "o" ) VALUE_o="$OPTARG" ;;
    "h" ) print_doc; print_usg
            exit 1 ;;
     \? ) print_doc; print_usg
            exit 1 ;;
  esac
done
shift `expr $OPTIND - 1`

# 1-2. コマンドライン引数の判定
if [[ "$#" != 1 && ! -d "$1" ]]; then
    echo "[ERROR] Either the directory is not specified or the directory cannot be found." >&2
    print_usg
    exit 1
fi

# 1-3. オプション引数の判定
if [[ -n "$VALUE_o" ]]; then OUTPUT=${VALUE_o}; else OUTPUT='manifest.txt'; fi
if [[ -z "$VALUE_d" ]]; then
  DIV=','
elif [[ "$VALUE_d" == '\t' ]] || [[ "$VALUE_d" == ',' ]]; then
  DIV="${VALUE_d}"
else 
  echo "[ERROR] The value for option -d must be a tab or comma." >&2
fi

# 1-4. プログラムに渡す引数の一覧
cat << EOS >&2
### Create a manifest file ###
output file path :            [ ${OUTPUT} ]
The delimetter of manifest :  [ ${DIV} ] 

EOS

### MAIN ###
# 2-1. fastqディレクトリの絶対パスを取得
# 2-2. ヘッダ行の生成 (csvの場合ペアエンドは別の行に記載する必要がある)
# 2-3. マニフェストファイル作成
###

# 2-1. fastqディレクトリの絶対パスを取得
FQD=`basename $1`
CPFQD=$(cd $(dirname $1) && pwd)/${FQD}

# 2-2. ヘッダ行の生成 (csvの場合ペアエンドは別の行に記載する必要がある)
if [[ "${DIV}" == "\t" && "${FLG_s}" == "TRUE" ]];then 
  echo -e sample-id${DIV}absolute-filepath > ${OUTPUT}
elif [[ "${DIV}" == "\t" && "${FLG_p}" == "TRUE" ]];then
  echo -e sample-id${DIV}forward-absolute-filepath${DIV}reverse-absolute-filepath > ${OUTPUT} 
elif [[ "${DIV}" == "," ]]; then 
  echo -e sample-id${DIV}absolute-filepath${DIV}direction > ${OUTPUT}
fi

# 2-3. マニフェストファイル作成
if [[ ${FLG_s} == "TRUE" && ${FLG_p} == "TRUE" ]] || [[ -z ${FLG_s} && -z ${FLG_p} ]]; then
  echo "[ERROR] -sまたは-pオプションのどちらかを選択する必要があります。"
  exit 1

elif [[ ${FLG_s} == "TRUE" && ${FLG_p} != "TRUE" ]]; then # single end
  ## ファイル名取得
  FQS=`ls $CPFQD | grep -e ".fastq$" -e ".fastq.gz$" -e ".fq$" -e ".fq.gz$"`
  ## マニフェストファイル作成 
  for r1 in ${FQS[@]} ; do
    ID=`echo ${r1%.*} | cut -f 1 -d "_"`
    cpfq_r1=${CPFQD}/${r1}
    if [[ "${DIV}" == "\t" ]];then # tsv
        echo -e ${ID}${DIV}${cpfq_r1} >> ${OUTPUT}
    elif [[ "${DIV}" == "," ]]; then # csv
        echo -e ${ID}${DIV}${cpfq_r1}${DIV}forward >> ${OUTPUT}
    fi
  done

elif [[ ${FLG_s} != "TRUE" && ${FLG_p} == "TRUE" ]]; then # paired-end
  ## ファイル名取得
  FQS=(`ls $CPFQD | grep -e "_R1" -e "_1" `) 
  ## マニフェストファイル作成 
  for r1 in ${FQS[@]}; do
    r2=`echo $r1 | sed -e 's/_R1/_R2/' -e 's/_1\./_2\./' `
    ID=`echo ${r1%.*} | cut -f 1 -d "_"`
    cpfq_r1=${CPFQD}/${r1}
    cpfq_r2=${CPFQD}/${r2}
    
    ## read1 & read2存在確認
    if [[ ! -f "${cpfq_r1}" || ! -f "${cpfq_r2}" ]]; then # read1 & read2存在確認
      echo "[ERROR] Either or both read1 and read2 files do not exist." >&2
      exit 1
    fi

    ## マニフェストファイル作成 
    if [[ "${DIV}" == "\t" ]];then # tsv 
        echo -e ${ID}${DIV}${cpfq_r1}${DIV}${cpfq_r2} >> ${OUTPUT}
    elif [[ "${DIV}" == "," ]]; then # csv
        echo -e ${ID}${DIV}${cpfq_r1}${DIV}forward >> ${OUTPUT}
        echo -e ${ID}${DIV}${cpfq_r2}${DIV}reverse >> ${OUTPUT}
    fi
  done
else
    print_doc
    exit 1
fi
