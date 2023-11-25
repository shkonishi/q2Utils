#!/bin/bash
VERSION=0.0.231124
AUTHOR=SHOGO_KONISHI
CMDNAME=$(basename $0)

### <CONTENTS> dada2を用いたデノイジング ###
# 1. ドキュメント
#  1.1. ヘルプの表示
#  1.2. 使用例の表示
# 2. オプション引数の処理
#  2.1. オプション引数の入力
#  2.2. オプション引数の判定
# 3. コマンドライン引数の処理
# 4. 引数の一覧
# 5. qiime2パイプライン実行 
#  5.1. qiime2起動
#  5.2. fastqインポート& Denoising
#  5.3. デノイジングのスタッツ, ASV, ASVテーブル をtxtファイルに変換
#  5.4. デノイジングのスタッツ, ASV, ASVテーブル をqzvファイルに変換
###


# 1. ドキュメント
#  1.1. ヘルプの表示
function print_doc() {
cat << EOS
使用法:
    $CMDNAME [オプション] manifest.txt
   
説明:
    このプログラムはペアエンドのアンプリコンシーケンスデータのqiime2へのインポート及び
    denoisingを実行します。manifestファイルがtsvの場合は、qiime tools importを実行する際に、
    --input-formatの値を[PairedEndFastqManifestPhred33V2]として実行しています。
    出力ファイルは以下のファイル名で固定しています。
        denoising-stats.qza     [denoising のスタッツ]
        seq.qza                 [ASV]
        table.qza               [ASV組成]

    それぞれのファイルはテキストファイルおよびqzvファイルにエクスポートされます。

オプション: 
  -s    シングルエンド
  -p    ペアエンド
  -e    conda環境変数パス[default: ${HOME}/miniconda3/etc/profile.d/conda.sh ]
  -q    qiime2環境名[default: qiime2-2021.8 ]
  -c    スレッド数[default: 4]
  -h    ヘルプドキュメントの表示

 qiime dada2 denoise-pairedにおけるオプション[--p-trunc-len-f/--p-trunc-len-r]に与える値
  -F    Read1 で切り捨てる位置[default: 280]
  -R    Read2 で切り捨てる位置[default: 210]

 qiime dada2 denoise-singleにおけるオプション[--p-trunc-len]に与える値
  -l    qualityフィルタリングの結果、この値より短いリードは破棄[default: 0]
        実際にはこの値のASV以外は捨てられてしまう。

使用例: 
    $CMDNAME -s manifest.txt    
    $CMDNAME -p manifest.txt
    $CMDNAME -p -F 270 -R 200 manifest.txt

    CENV=\${HOME}/miniconda3/etc/profile.d/conda.sh
    QENV='qiime2-2022.2'
    $CMDNAME -e \$CENV -q \$QENV -c 6 -s manifest.txt
  
EOS
}
if [[ "$#" = 0 ]]; then print_doc ; exit 1 ; fi

# 2. オプション引数の処理
#  2.1. オプション引数の入力
while getopts spe:q:c:F:R:l:h OPT
do
  case $OPT in
    "s" ) FLG_s="TRUE" ;;
    "p" ) FLG_p="TRUE" ;;
    "e" ) VALUE_e="$OPTARG";;
    "q" ) VALUE_q="$OPTARG";;
    "c" ) VALUE_c="$OPTARG";;
    "F" ) VALUE_F="$OPTARG";;
    "R" ) VALUE_R="$OPTARG";;
    "l" ) VALUE_l="$OPTARG";;
    "h" ) print_doc ; exit 1 ;; 
    * ) print_doc ; exit 1;; 
    \? ) print_doc ; exit 1 ;;
  esac
done
shift $(expr $OPTIND - 1)

#  2.2. オプション引数の判定
#   2.2.1. conda環境変数ファイルの存在確認
if [[ -z "$VALUE_e" ]]; then CENV="${HOME}/miniconda3/etc/profile.d/conda.sh"; else CENV=${VALUE_e}; fi
if [[ ! -f "${CENV}" ]]; then
 echo "[ERROR] The file for the conda environment variable cannot be found. ${CENV}" >&2
 print_usg
 exit 1
fi

#   2.2.2. qiime2環境の存在確認
if [[ -z "$VALUE_q" ]]; then QENV="qiime2-2022.2"; else QENV=${VALUE_q}; fi
if conda info --envs | awk '!/^#/{print $1}'| grep -q "^${QENV}$" ; then
    :
else 
    echo "[ERROR] There is no ${QENV} environment." >&2
    conda info --envs
    print_usg
    exit 1
fi

#   2.2.3. その他オプション引数の判定および、デフォルト値の指定
if [[ "${FLG_s}" == "TRUE" && "${FLG_p}" != "TRUE" ]]; then 
    DRCTN="single"
    if [[ -z "$VALUE_l" ]]; then TRUNKL=0; else TRUNKL=${VALUE_l}; fi

elif [[ "${FLG_s}" != "TRUE" && "${FLG_p}" == "TRUE" ]]; then
    DRCTN="paired"
    if [[ -z "${VALUE_F}" || -z "${VALUE_R}" ]]; then
        TRUNKF=270; TRUNKR=200
    elif [[ -n "${VALUE_F}" && -n "${VALUE_R}" ]]; then 
        TRUNKF=${VALUE_F}; TRUNKR="${VALUE_R}"
    else 
        echo -e "[ERROR]"
        exit 1
    fi
else 
    echo "[ERROR] The optin flag [-s|-p] must be set."
    exit 1
fi
if [[ -z "$VALUE_c" ]]; then NT=4; else NT=${VALUE_c};fi
OUTD='exported_txt'
if [[ -d "${OUTD}" ]];then echo "[WARNING] ${OUTD} already exists. The output files may be overwritten." >&2 ; fi
OUTDZ='exported_qzv'
if [[ -d "${OUTDZ}" ]]; then echo "[WARNING] ${OUTDZ} already exists. The output files may be overwritten." >&2 ; fi

# 3. コマンドライン引数の処理
## マニフェストファイル形式判定 
if [[ "$#" = 1 && -f "$1" ]]; then
    MNFST=$1
    TMNF=$(cat ${MNFST} | awk -F"\t" '{print NF}'| uniq)
    CMNF=$(cat ${MNFST} | awk -F"," '{print NF}'| uniq)
    if [[ "${TMNF}" == 2 || "${TMNF}" == 3 ]] && [[ "${CMNF}" != 3 ]] ; then
        MFMT="tsv"
    elif [[ "${TMNF}" != 2 && "${TMNF}" != 3 ]] && [[ "${CMNF}" == 3 ]] ; then
        MFMT="csv"
    else 
        echo "[ERROR] The input file must be csv or tsv ." >&2
        exit 1
    fi

else 
    echo "[ERROR] The manifest file, ${1}, not found" >&2
    print_usg
    exit 1
fi

# 4. プログラムに渡す引数の一覧
cat << EOS >&2
### Denoising ###
conda environmental variables                           [ ${CENV} ]
qiime2 environment                                      [ ${QENV} ]
Manifest file                                           [ ${MNFST} ]
Format of manifest file :                               [ ${MFMT} ]
Paired/Single end :                                     [ ${DRCTN} ]
The position to be truncated at Read1:                  [ ${TRUNKF} ]
The position to be truncated at Read2                   [ ${TRUNKR} ]
Reads shorter than this value will be discarded(single) [ ${TRUNKL} ]
Number of threads :                                     [ ${NT} ]

EOS

# 5. qiime2パイプライン実行 
#  5.1. qiime2起動
source ${CENV}
if echo ${CENV} | grep -q "anaconda" ; then 
 source activate ${QENV}
 else conda activate ${QENV}
fi

#  5.2. fastqインポート& Denoising
if [[ "${DRCTN}" == "single" ]]; then
    # input formatの指定
    if [[ "${MFMT}" == "csv" ]]; then 
        INFMT='SingleEndFastqManifestPhred33' 
    elif [[ "${MFMT}" == "tsv" ]]; then 
        INFMT='SingleEndFastqManifestPhred33V2' 
    fi

    #  qiime tools import
    echo "# [CMND] Import fastq files from manifest." >&2
    cmd1="qiime tools import --type SampleData[SequencesWithQuality] --input-path ${MNFST} --output-path seq.qza --input-format ${INFMT}"
    echo ${cmd1} >&2 ; eval ${cmd1}

    # seq.qza がなければexit
    if [[ ! -f seq.qza ]]; then echo "[ERROR] The seq.qza was not output."; exit 1; fi

    # qiime dada2 denoise-
    echo "# [CMND] Denoising of single end reads." >&2
    cmd2="qiime dada2 denoise-single --i-demultiplexed-seqs seq.qza --p-trunc-len ${TRUNKL} \
    --o-representative-sequences repset.qza --o-table table.qza --p-n-threads ${NT} --o-denoising-stats denoising-stats.qza"
    echo ${cmd2} >&2 ; eval ${cmd2}

    ## table.qza がなければexit
    if [[ ! -f table.qza || ! -f denoising-stats.qza ]]; then echo "[ERROR] The table.qza was not created."; exit 1; fi

elif [[ "${DRCTN}" == "paired" ]]; then
    #  input formatの指定
    if [[ "${MFMT}" == "csv" ]]; then 
        INFMT='PairedEndFastqManifestPhred33' 
    elif [[ "${MFMT}" == "tsv" ]]; then 
        INFMT='PairedEndFastqManifestPhred33V2' 
    else 
        echo -e "[ERROR] The manifest file must be 'csv' or 'tsv'. "
        exit 1
    fi

    #  qiime tools import
    echo "# [CMND] Import fastq files from manifest." >&2
    cmd3="qiime tools import --type SampleData[PairedEndSequencesWithQuality] --input-path ${MNFST} --output-path seq.qza --input-format ${INFMT}"
    echo ${cmd3} >&2 ; eval ${cmd3}

    ## seq.qza ができなければexit
    if [[ ! -f seq.qza ]]; then echo "[ERROR] The seq.qza was not output."; exit 1; fi

    # qiime dada2 denoise-
    echo "# [CMND] Denoising of paired-end reads." >&2
    cmd4="qiime dada2 denoise-paired --i-demultiplexed-seqs seq.qza \
    --p-trunc-len-f ${TRUNKF} --p-trunc-len-r ${TRUNKR} \
    --o-representative-sequences repset.qza --o-table table.qza \
    --p-n-threads ${NT} --o-denoising-stats denoising-stats.qza"
    echo ${cmd4} >&2 ; eval ${cmd4}

    ## table.qza がなければexit
    if [[ ! -f table.qza ]]; then echo "[ERROR] The table.qza was not output."; exit 1; fi

fi

#  5.3. デノイジングのスタッツ, ASV, ASVテーブル をtxtファイルに変換
## 出力ディレクトリを確認
if [[ ! -d "${OUTD}" ]];then mkdir ${OUTD} ; fi

## デノイジングのスタッツをTSVに変換
unzip -q denoising-stats.qza -d ./dnz
mv ./dnz/*/data/stats.tsv ./${OUTD}/denoise_stats.tsv
rm -r ./dnz

## ASVをfasta形式に変換 [./${OUTD}/dna-sequences.fasta]
echo "# [CMND] Export ASV sequence to a fasta file." >&2
cmd5="qiime tools export --input-path  repset.qza --output-path ${OUTD}"
echo ${cmd5} >&2 ; eval ${cmd5}

## ASVテーブルをTSVに変換
echo "# [CMND] Export feature-table to a biome file and convert to tsv format." >&2
cmd6="qiime tools export --input-path table.qza --output-path ${OUTD}"
cmd7="biom convert -i ./${OUTD}/feature-table.biom -o ./${OUTD}/feature-table.tsv --to-tsv"
echo ${cmd6} >&2 ; eval ${cmd6}
echo ${cmd7} >&2 ; eval ${cmd7}

#  5.4. デノイジングのスタッツ, ASV, ASVテーブル をqzvファイルに変換
## 出力ディレクトリを確認
if [[ ! -d "${OUTDZ}" ]]; then mkdir ${OUTDZ} ; fi

## デノイジングのスタッツをqzvに変換
echo "# [CMND] Export denoising stats in qzv format." >&2
cmd8="qiime metadata tabulate --m-input-file denoising-stats.qza --o-visualization ./${OUTDZ}/denoising-stats.qzv"
echo ${cmd8} >&2 ; eval ${cmd8}

## 代表配列をqzvに変換
echo "# [CMND] Export ASV sequence in qzv format." >&2
cmd9="qiime feature-table tabulate-seqs --i-data repset.qza --o-visualization ./${OUTDZ}/repset.qzv"
echo ${cmd9} >&2 ; eval ${cmd9}

## ASVテーブルをqzvに変換
echo "# [CMND] Export feature-table in qzv format." >&2
cmd10="qiime feature-table summarize --i-table table.qza --o-visualization ./${OUTDZ}/table.qzv"
echo ${cmd10} >&2 ; eval ${cmd10}

exit 0