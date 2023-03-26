#!/bin/bash
VERSION=0.1.230224
AUTHOR=SHOGO_KONISHI
CMDNAME=`basename $0`

# ヘルプの表示
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
        実際にはこの値のASV以外は捨てられてしまう(バグではないかと思われる)。
  
EOS
}

# 使用法の表示
function print_usg() {
cat << EOS >&2
使用例: 
    $CMDNAME -s manifest.txt    
    $CMDNAME -p manifest.txt
    $CMDNAME -p -F 270 -R 200 manifest.txt

EOS
}

### 引数チェック ###
# 1-1. オプションの入力処理 
# 1-2. conda環境変数ファイルの存在確認
# 1-3. qiime2環境の存在確認
# 1-4. コマンドライン引数の判定 
# 1-5. オプション引数の判定
# 1-6. プログラムに渡す引数の一覧
###

# 1-1. オプションの入力処理 
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
if [[ ! -f "${CENV}" ]]; then
 echo "[ERROR] The file for the conda environment variable cannot be found. ${CENV}"
 print_usg
 exit 1
fi

# 1-3. qiime2環境の存在確認
if [[ -z "$VALUE_q" ]]; then QENV="qiime2-2022.2"; else QENV=${VALUE_q}; fi
if conda info --envs | awk '!/^#/{print $1}'| grep -qx "^${QENV}$" ; then
    :
else 
    echo "[ERROR] There is no ${QENV} environment."
    conda info --envs
    print_usg
    exit 1
fi

# 1-4. コマンドライン引数の判定, マニフェストファイル形式判定 
if [[ "$#" = 1 && -f "$1" ]]; then
    MNFST=$1
    TMNF=`cat ${MNFST} | awk -F"\t" '{print NF}'| uniq`
    CMNF=`cat ${MNFST} | awk -F"," '{print NF}'| uniq`
    if [[ "${TMNF}" == 2 || "${TMNF}" == 3 ]] && [[ "${CMNF}" != 3 ]] ; then
        MFMT="tsv"
    elif [[ "${TMNF}" != 2 && "${TMNF}" != 3 ]] && [[ "${CMNF}" == 3 ]] ; then
        MFMT="csv"
    else 
        echo "[ERROR] The input file must be csv or tsv ."
        exit 1
    fi

else 
    echo "[ERROR] The manifest file, ${1}, not found"
    print_usg
    exit 1
fi

# 1-5. オプション引数の判定
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

# # manifestファイルからpaired/single を判定する。 -> オプション指定に変更
# DIRECTIONS=(`cat manifest.txt | awk -F"," 'NR>1{print $NF}' | sort | uniq`)
# if printf '%s\n' "${DIRECTIONS[@]}" | grep -qx "forward"  && \
#    printf '%s\n' "${DIRECTIONS[@]}" | grep -qx "reverse" ; then 
#     REND="paired"
# elif printf '%s\n' "${DIRECTIONS[@]}" | grep -qx "forward"  && \
#      [[ $(printf '%s\n' "${DIRECTIONS[@]}" | grep -qx "reverse"; echo -n ${?} ) -eq 1 ]]; then
#     REND="single" 
# else
#     echo "[ERROR] The Direction on the manifest file must be 'forward/single' ."
#     exit 1
# fi

# 1-6. プログラムに渡す引数の一覧
cat << EOS >&2
### Denoising ###
conda environmental variables :                             [ ${CENV} ]
qiime2 environment :                                        [ ${QENV} ] 
Manifest file:                                              [ ${MNFST} ] 
Format of manifest file :                                   [ ${MFMT} ]  
Paired/Single end :                                         [ ${DRCTN} ]
The position to be truncated at Read1:                      [ ${TRUNKF} ]
The position to be truncated at Read2:                      [ ${TRUNKR} ]
Reads shorter than this value will be discarded(single).    [ ${TRUNKL} ]
Number of threads :                                         [ ${NT} ] 
EOS


### MAIN ###
#   2-1. qiime2起動
#   2-2. fastqインポート& Denoising
#   2-3. デノイジングのスタッツ, ASV, ASVテーブル をtxtファイルに変換
#   2-4. デノイジングのスタッツ, ASV, ASVテーブル をqzvファイルに変換
### 

# 2-1. qiime2起動
source ${CENV}
if echo ${CENV} | grep -qx "anaconda" ; then 
 source activate ${QENV}
 else conda activate ${QENV}
fi


# 2-2. fastqのインポートとデノイジング
if [[ "${DRCTN}" == "single" ]]; then
    # input formatの指定
    if [[ "${MFMT}" == "csv" ]]; then 
        INFMT='SingleEndFastqManifestPhred33' 
    elif [[ "${MFMT}" == "tsv" ]]; then 
        INFMT='SingleEndFastqManifestPhred33V2' 
    fi

    #  qiime tools import 
    qiime tools import \
    --type SampleData[SequencesWithQuality] \
    --input-path ${MNFST} \
    --output-path seq.qza \
    --input-format ${INFMT}

    # seq.qza がなければexit
    if [[ ! -f seq.qza ]]; then echo "[ERROR] The seq.qza was not output."; exit 1; fi

    # qiime dada2 denoise-
    qiime dada2 denoise-single \
    --i-demultiplexed-seqs seq.qza \
    --p-trunc-len ${TRUNKL} \
    --o-representative-sequences repset.qza \
    --o-table table.qza \
    --p-n-threads ${NT} \
    --o-denoising-stats denoising-stats.qza

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
    qiime tools import \
    --type SampleData[PairedEndSequencesWithQuality] \
    --input-path ${MNFST} \
    --output-path seq.qza \
    --input-format ${INFMT}

    ## seq.qza ができなければexit
    if [[ ! -f seq.qza ]]; then echo "[ERROR] The seq.qza was not output."; exit 1; fi

    # qiime dada2 denoise-
    qiime dada2 denoise-paired \
    --i-demultiplexed-seqs seq.qza \
    --p-trunc-len-f ${TRUNKF} \
    --p-trunc-len-r ${TRUNKR} \
    --o-representative-sequences repset.qza \
    --o-table table.qza \
    --p-n-threads ${NT} \
    --o-denoising-stats denoising-stats.qza

    ## table.qza がなければexit
    if [[ ! -f table.qza ]]; then echo "[ERROR] The table.qza was not output."; exit 1; fi

fi

# 2-3. デノイジングのスタッツ, ASV, ASVテーブル をtxtファイルに変換
## 出力ディレクトリを確認
OUTD='exported_txt'
if [[ -d "${OUTD}" ]];then
    echo "[WARNING] ${OUTD} already exists. The output files may be overwritten." 
else 
    mkdir ${OUTD}
fi

## デノイジングのスタッツをTSVに変換
unzip -q denoising-stats.qza -d ./dnz
mv ./dnz/*/data/stats.tsv ./${OUTD}/denoise_stats.tsv
rm -r ./dnz

## ASVをfasta形式に変換 [./${OUTD}/dna-sequences.fasta] 
qiime tools export --input-path  repset.qza --output-path ${OUTD}

## ASVテーブルをTSVに変換
qiime tools export --input-path table.qza --output-path ${OUTD}
biom convert -i ./${OUTD}/feature-table.biom -o ./${OUTD}/feature-table.tsv --to-tsv


# 2-4. デノイジングのスタッツ, ASV, ASVテーブル をqzvに変換 
## 出力ディレクトリを確認
OUTDZ='exported_qzv'
if [[ -d "${OUTDZ}" ]]; then
    echo "[WARNING] ${OUTDZ} already exists. The output files may be overwritten."
else 
    mkdir ${OUTDZ}
fi

## デノイジングのスタッツをqzvに変換
qiime metadata tabulate \
--m-input-file denoising-stats.qza \
--o-visualization ./${OUTDZ}/denoising-stats.qzv

## 代表配列をqzvに変換
qiime feature-table tabulate-seqs \
--i-data repset.qza \
--o-visualization ./${OUTDZ}/repset.qzv

## ASVテーブルをqzvに変換
qiime feature-table summarize \
--i-table table.qza \
--o-visualization ./${OUTDZ}/table.qzv

# qiime2 no stdout ? stderrout ?
# Imported manifest.txt as PairedEndFastqManifestPhred33 to seq.qza
# Saved FeatureTable[Frequency] to: table.qza
# Saved FeatureData[Sequence] to: repset.qza
# Saved SampleData[DADA2Stats] to: denoising-stats.qza
# Exported repset.qza as DNASequencesDirectoryFormat to directory exported_txt
# Exported table.qza as BIOMV210DirFmt to directory exported_txt
# Saved Visualization to: ./exported_qzv/denoising-stats.qzv
# Saved Visualization to: ./exported_qzv/repset.qzv