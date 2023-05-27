#!/bin/bash
VERSION=0.1.230403
AUTHOR=SHOGO_KONISHI
CMDNAME=`basename $0`

### Contents: Merge taxonomy and feature table ###
# 1. ドキュメント
#  1.1. ヘルプの表示 
#  1.2. 使用例の表示
# 2. オプション引数の処理
# 3. コマンドライン引数の処理
# 4. プログラムに渡す引数の一覧 
# 5. qiime2パイプライン実行 
#  5.1. qiime2起動
#  5.2. 関数定義 
#  5.3. qza ファイルを一時ディレクトリに展開
#  5.4. データを結合
#  5.5. ASVの系統樹を作成
#  5.6. 一時ファイルの移動, 削除
###


# 1. ドキュメント
#  1.1. ヘルプの表示
function print_doc() {
cat << EOS
使用法:
    $CMDNAME [オプション] <taxonomy.qza> 

用語の定義およびこのプログラム中で使用されるデフォルトファイル名:
    ASV配列     Denoisingされた配列 [repset.qza]
    ASVテーブル  検体に含まれるASVのリードカウントテーブル. qiime2的にはfeature-table [table.qza]
    taxonomy    ASVの系統推定結果 qiime feature-classifierの出力 [taxonomy.qza]
    系統組成表   taxonomyデータとASVテーブルを結合したもの [taxonomy_cnt.tsv]

説明:
    このプログラムはqiime2が出力したASVテーブルとtaxonomyデータの結合(系統組成表)、
    またはASV配列とtaxonomyデータの結合のいずれかまたは両方を実行します。
    もう一つの機能として、ノードラベルをtaxonomic-nameに変換したASV配列の系統樹を作成します。

    入力ファイルはコマンドライン引数にtaxonomyデータ[taxonomy.qza]を指定し、
    オプション引数としてASVテーブル[table.qza]またはASV配列[repset.qza]のいずれかまたは両方を指定してください。
    いずれもqza形式で指定します。結合された出力ファイルは[taxonomy_cnt.tsv|taxonomy_asv.tsv]として、
    tsv形式で書き出されます。

    ASV配列の系統樹を作成する場合、uオプションを指定することで、系統アサインされなかったASVは除去できます。
    qiime2の出力するnewick形式のASVツリーでは、各ノードがASVのハッシュ値となっているため上記の系統組成表を基にして
    taxonomic-nameに変換して出力します。
    
オプション: 
  -e    conda環境変数パス[default: ${HOME}/miniconda3/etc/profile.d/conda.sh ]
  -q    qiime2環境名[default: qiime2-2021.8 ]
  -t    ASVテーブル [default: table.qza]
  -s    ASV配列 [default: repset.qza]
  -o    出力ファイル名[default: taxonomy_cnt.tsv]
  -u    系統樹作成の際に、Unassignedタクソンを除外
  -h    ヘルプドキュメントの表示
EOS
}
#  1.2. 使用例の表示
function print_usg() {
cat << EOS
使用例: 
    $CMDNAME -h                                         # ドキュメントの表示
    $CMDNAME -t table.qza taxonomy.qza                  # ASVテーブルとtaxonomyの結合      
    $CMDNAME -s repset.qza taxonomy.qza                 # ASV配列とtaxonomyの結合 & ASV-tree構築
    $CMDNAME -t table.qza -s repset.qza taxonomy.qza    # 上記2つを実行
    $CMDNAME -t table.qza -s repset.qza -u taxonomy.qza # ASV-treeからUnassigned taxon除去

    CENV=\${HOME}/miniconda3/etc/profile.d/conda.sh
    QENV='qiime2-2021.8'
    $CMDNAME -e \$CENV -q \$QENV  -t table.qza taxonomy.qza

EOS
}

# 2. オプション引数の処理
#  2.1. オプション引数の入力
while getopts e:q:t:s:o:uh OPT
do
  case $OPT in
    "e" ) CENV="$OPTARG";;
    "q" ) QENV="$OPTARG";;
    "t" ) FLG_t="TRUE"; VALUE_t="$OPTARG";;
    "s" ) FLG_s="TRUE"; VALUE_s="$OPTARG";;
    "o" ) VALUE_o="$OPTARG";;
    "u" ) FLG_u="TRUE" ;;
    "h" ) print_doc ; print_usg ; 
            exit 1 ;; 
    *) print_doc
        exit 1;; 
    \? ) print_doc ; print_usg
            exit 1 ;;
  esac
done
shift `expr $OPTIND - 1`

#  2.2. オプション引数の判定およびデフォルト値の指定
## conda環境変数ファイルの存在確認
if [[ -z "${CENV}" ]]; then CENV="${HOME}/miniconda3/etc/profile.d/conda.sh"; fi
if [[ ! -f "${CENV}" ]]; then
 echo "[ERROR] The file for the conda environment variable cannot be found. ${CENV}"
 print_usg
 exit 1
fi
## qiime2環境の存在確認
if [[ -z "${QENV}" ]]; then QENV="qiime2-2022.8"; fi
if conda info --envs | awk '!/^#/{print $1}'| grep -q "^${QENV}$" ; then
    :
else 
    echo "[ERROR] The conda environment ${QENV} was not found."
    conda info --envs
    print_usg
    exit 1
fi


## ASV配列及の判定
if [[ -z "${VALUE_s}" && -z "${VALUE_t}" ]]; then echo "[ERROR] Either or both options t/s must be selected."; exit 1 ; fi
if [[ -n "${VALUE_s}" ]]; then
    SEQ=${VALUE_s} # input
    OTF='taxonomy_asv.tsv' # output
    if [[ ! -f ${SEQ} || ${SEQ##*.} != 'qza' ]] ; then 
        echo "[ERROR] The ASV sequence, ${SEQ}, does not exist or is not in qza format." 
        exit 1
    fi
fi

## ASV-tableの判定
if [[ -n "${VALUE_t}" ]]; then
    TAB=${VALUE_t}
    if [[ ! -f ${TAB} || ${TAB##*.} != 'qza' ]] ; then 
        echo "[ERROR] The ASV table ${TAB} does not exist or is not in qza format." 
        exit 1
    fi
fi

## その他オプション引数の判定 
if [[ -z "${VALUE_o}" ]]; then OTT="taxonomy_cnt.tsv"; else OTT=${VALUE_o}; fi
OUTCNT='count_table'
if [[ -d "${OUTCNT}" ]]; then echo "[WARNING] ${OUTCNT} was already exists. The output files may be overwritten." >&2 ; fi
if [[ -z "${VALUE_s}" ]]; then unset OTF ;  elif [[ -z "${VALUE_t}" ]]; then unset OTT; unset OUTCNT; fi


# 3. コマンドライン引数の処理 
if [[ $# = 1 ]]; then
    TAX=$1
    if [[ ! -f ${TAX} || ${TAX##*.} != 'qza' ]] ; then 
        echo "[ERROR] The taxonomy data ${TAX} does not exist or is not in qza format." ; exit 1
    fi   
else
    echo "[ERROR] コマンドライン引数としてtaxonomyデータ(qza形式)が必要です。";  print_usg; exit 1
fi

# 4. プログラムに渡す引数の一覧
cat << EOS >&2
### Merge taxonomy into count data, ASV sequences, and ASV trees ###
conda environmental values :          [ ${CENV} ]
qiime2 environment :                  [ ${QENV} ]

Input taxonomy file path:             [ ${TAX} ]
Input ASV table file path:            [ ${TAB} ]
Input ASV file path:                  [ ${SEQ} ]

Output taxonomy count table:          [ ${OTT} ]
Output taxonomy ASV sequence table:   [ ${OTF} ]
Output count table summarized by rank [ ${OUTCNT} ]

EOS

# 5. qiime2パイプライン実行 
#  5.1. qiime2起動
source ${CENV}
if echo ${CENV} | grep -q "anaconda" ; then source activate ${QENV}; else conda activate ${QENV}; fi

# 5.2. 関数定義 
## 5.2.1 関数定義, ASVテーブルとtaxonomyデータとASV配列を結合
function mtax () {
    TTAX=$1; TTAB=$2 
    # カウントデータからヘッダ行抽出
    HD=(`grep "^#OTU ID" ${TTAB} | sed 's/^#OTU ID//'`)
    # taxonomyデータからrankの配列を取り出す (7列もしくは8列の場合がある)
    RANK=(`cut -f2 $TTAX | awk -F"; " '{if(NF==8){ \
    sub("_.*","",$1);sub("_.*","",$2);sub("_.*","",$3);sub("_.*","",$4); \
    sub("_.*","",$5); sub("_.*","",$6);sub("_.*","",$7); sub("_.*","",$8); \
    print $1" "$2" "$3" "$4" "$5" "$6" "$7" "$8;} \
    else if(NF==7){sub("_.*","",$1);sub("_.*","",$2);sub("_.*","",$3);sub("_.*","",$4); \
    sub("_.*","",$5); sub("_.*","",$6);sub("_.*","",$7); print $1" "$2" "$3" "$4" "$5" "$6" "$7;}}' | head -1`)
    # ヘッダ行作成
    HDC=(`echo ASV_ID confidence ${RANK[@]} ${HD[@]}`)

    # idの同一性チェック(taxonomyとASVテーブルをマージする場合)
    id_tab=(`grep -v "^#" ${TTAB} | awk -F"\t" '{print $1}'`)
    id_tax=(`grep -v "^Feature" ${TTAX} | awk -F"\t" '{print $1}'`)
    un1=(`echo ${id_tab[*]} ${id_tax[*]} | tr ' ' '\n' | sort | uniq -c | awk '{print $1 }' | uniq`) 

    # Merge 
    if [[ ${#un1[@]} == 1 && ${un1[@]} == 2 ]]; then
        NC=`cat ${TTAX} | cut -f2 | awk -F"; " '{print NF}' | sort -u | sort -nr | head -1`
        echo ${HDC[@]} | tr ' ' '\t' ;
        paste <(cat ${TTAX} | awk -F"\t" 'NR>1{print $1"\t"$3}' | sort -k1,1 ) \
        <(cat ${TTAX} | awk -F"\t" 'NR>1{print $1"\t"$2}' | sort -k1,1 | cut -f2 \
        | awk -F"; " -v NC=${NC} '{if(NC==8){print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7"\t"$8 } \
        else if(NC==7){print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7 }}') \
        <( awk 'NR>2{print}' ${TTAB} | sort -k1,1 | cut -f 2- )
        
    else 
        echo "[ERROR] The file format of inputs was invalid."
    fi
}
## 5.2.2 関数定義, taxonomyデータとASV配列を結合
function mtseq () {
    TTAX=$1; TSEQ=$2; 
    id_tax=(`grep -v "^Feature" ${TTAX} | awk -F"\t" '{print $1}'`)
    id_seq=(`grep "^>" ${TSEQ} | sed 's/^>//'`)
    un=(`echo ${id_tax[*]} ${id_seq[*]} | tr ' ' '\n' | sort | uniq -c | awk '{print $1 }' | uniq`)

    if [[ ${#un[@]} == 1 && ${un[@]} == 2 ]]; then
        #echo ${HDC[@]} | tr ' ' '\t'
        paste <(cat ${TTAX} | awk -F"\t" 'NR>1{print $1"\t"$3}' | sort -k1,1 ) \
        <(cat ${TTAX} | awk -F"\t" 'NR>1{print $1"\t"$2}' | sort -k1,1 | awk -F"\t" '{print $2}'\
        | awk -F"; " '{print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7}') \
        <( cat ${TSEQ} | awk 'BEGIN{RS=">"; FS="\n"} NR>1 {print $1"\t"$2;}' | sort -k1,1 | cut -f 2-)
    else 
        echo "[ERROR] The file format of inputs was invalid."
    fi

}
## 5.2.3 関数定義, taxonomyデータから最も下位のタクソンを抽出, リファレンスで記述が異なる
function id_tax () {
    paste <(cut -f1 ${1}| awk 'NR>1' ) \
    <(cut -f2 ${1} | awk -F"; " 'BEGIN{i=NF}NR>1{for (i = NF; i > 0; i-- ){if($i!~/__$/){print $i;break}else if($i~/__$/){} }}' )
}
## 5.2.4 関数定義, fastaファイルから指定idの配列除外
function faGetrest (){
  id=(${1}); fa=$2; rest=$3
  cat ${fa} \
  | awk '/^>/ { print n $0; n = "" }!/^>/ { printf "%s", $0; n = "\n" } END{ printf "%s", n }' \
  | awk 'BEGIN{RS=">"; FS="\n"} NR>1 {print $1"\t"$2;}' \
  | awk 'NR==FNR{a[$1]=$1}NR!=FNR{if ($1 in a) ; else print ">"$1"\n"$2 > "'${rest}'"}' \
  <(echo ${id[@]} | tr ' ' '\n' ) -
}
# 5.3. qza ファイルを一時ディレクトリに展開
## 5.3.1 taxonomyファイルの展開 ${TAXTSV}
temp_tax=$(mktemp -d)
trap 'rm -rf $temp_tax' EXIT
unzip -q ${TAX} -d $temp_tax
TAXTSV="${temp_tax}/*/data/taxonomy.tsv"

if [[ ! -f $(echo $TAXTSV) ]] ; then 
    echo -e "[ERROR] The specified argument ${TAX} may not be a taxonomy."
    exit 1 
fi

## 5.3.2 ASVテーブルを展開 ${BIOME}
if [[ -n "${TAB}" ]]; then
    temp_tab=$(mktemp -d)
    trap 'rm -rf ${temp_tab}' EXIT
    unzip -q ${TAB} -d ${temp_tab}
    BIOME="${temp_tab}/*/data/feature-table.biom" 
    if [[ ! -f $(echo ${BIOME}) ]] ; then
        echo -e "[ERROR] ${TAB} may not be a feature table. "
        exit 1
    fi
fi
## 5.3.3 ASV配列の展開 ${ASVFA}
if [[ -n "${SEQ}" ]]; then
    temp_seq=$(mktemp -d)
    trap 'rm -rf ${temp_seq}' EXIT
    unzip -q ${SEQ} -d ${temp_seq} 
    ASVFA="${temp_seq}/*/data/dna-sequences.fasta"

    if [[ ! -f $(echo ${ASVFA}) ]] ; then
        echo -e "[ERROR] ${SEQ} may not be a ASV fasta. "
        exit 1
    fi

fi

# 5.4. データを結合
if [[ -f $(echo ${ASVFA}) && -f $(echo ${BIOME}) ]] ; then
    ## taxonomyデータとの結合 feature-table & ASV-fasta
    biom convert -i ${BIOME} -o ./feature-table.tsv --to-tsv 
    mtax ${TAXTSV} feature-table.tsv > ${OTT}
    mtseq ${TAXTSV} ${ASVFA} > ${OTF} 

elif [[ -f $(echo ${BIOME}) ]]; then
    ## taxonomyデータとfeature-tableを結合
    biom convert -i ${BIOME} -o ./feature-table.tsv --to-tsv 
    mtax ${TAXTSV} feature-table.tsv > ${OTT}

elif [[ -f $(echo ${ASVFA}) ]]; then
    ## taxonomyデータとASV配列を結合
    mtseq ${TAXTSV} ${ASVFA} > ${OTF}
else 
    echo -e "[ERROR] The ${SEQ} may not be an ASV sequence. "
    exit 1
fi

# 5.5. 系統組成表をtaxonomic rankごとに分割して要約
## 系統組成表存在確認
if [[ ! ${FLG_t} = "TRUE" && ! -f ${OTT} ]]; then 
  echo -e "[INFO] DONE" ; exit 1 ; 
fi
mkdir -p ${OUTCNT}

## taxonomicランク列及びサンプル列を指定　
ncol=`head -1 ${OTT} | awk -F"\t" '{print NF}'`
ismp=10
smps=(`head -1 ${OTT} | cut -f${ismp}-`)
ntax=(`seq 3 $((${ismp}-1))`)
nsmp=(`seq ${ismp} ${ncol}`)

## taxonomic rankの判定　silva, greengene, pr2
rank1=`head -1 ${OTT} | cut -f3`; rank2=`head -1 ${OTT} | cut -f4`
if [[ $rank1 = 'd' && $rank2 = 'p' ]]; then
  rank=(domain phylum class order family genus species)
elif [[ $rank1 = 'k' && $rank2 = 'p' ]]; then
  rank=(kingdom phylum class order family genus species)
elif [[ $rank1 = 'd' && ! $rank2 = 'p' ]]; then
  rank=(domain supergroup phylum class order family genus species)
fi

## Check args
# echo -e "[Names of samples]\t"${smps[@]}
# echo -e "[Names of taxonomic rank]\t"${rank[@]}

## 一時ファイルを格納するディレクトリ
temp_cnt=$(mktemp -d)
trap 'rm -rf $temp_cnt' EXIT

## rank毎に行持ちデータフレームを作成し、要約
for j in ${!ntax[@]}; do
  ptax=${ntax[$j]}; tax=${rank[$j]}
  for i in ${!nsmp[@]}; do
    psmp=${nsmp[$i]}; smp=${smps[$i]}
    cut -f${ptax},${psmp} ${OTT} | sed -e '1d' \
    | awk -F"\t" -v smp="${smp}" '{if($1==""){$1="Unassigned"}; arr[$1]+=$2}END{for(x in arr)print x"\t"smp"\t"arr[x]}'
  done > ${temp_cnt}/${tax}.cnt
done

## 列持ちデータに変換
abr=(`for i in ${rank[@]}; do echo ${i:0:1}; done`)
for k in ${!rank[@]}; do 
  rnk=${rank[$k]}
  in=${temp_cnt}/${rnk}.cnt
  out=${OUTCNT}/count_${abr[$k]}.dat

 for x in ${smps[@]}; do 
  grep ${x} ${in} | cut -f1,3 | sort -t$'\t' -k1,1 > ${temp_cnt}/${rnk}_${x}.tmp
 done
 
n_temp=`ls ${temp_cnt}/*.tmp | wc -l` # sample numbers
slct=(`seq 2 2 $((${n_temp}*2))`) # column numbers of count data only
echo -e "taxon "${smps[*]} | tr ' ' '\t' > ${out}
paste ${temp_cnt}/${rnk}*.tmp | cut -f1,`echo ${slct[@]}|tr ' ' ','`  >> ${out}

done

# 5.6. 一時ファイルの移動, 削除
if [[ -f feature-table.tsv ]];then rm feature-table.tsv; fi