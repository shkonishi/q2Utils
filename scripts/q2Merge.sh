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
  -n    ASVテーブルとASV配列から、最大読み取り回数がn回以下の配列を削除 [default: 0 ] 
        qiime feature-table filter-featuresは不使用
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
while getopts e:q:t:s:n:o:uh OPT
do
  case $OPT in
    "e" ) CENV="$OPTARG";;
    "q" ) QENV="$OPTARG";;
    "t" ) FLG_t="TRUE"; VALUE_t="$OPTARG";;
    "s" ) FLG_s="TRUE"; VALUE_s="$OPTARG";;
    "n" ) VALUE_n="$OPTARG" ;;
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
if [[ -z "${VALUE_s}" || -z "${VALUE_t}" ]]; then echo "[ERROR] Both options t/s must be selected."; exit 1 ; fi
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
if [[ -z "${VALUE_n}" ]]; then 
  DP=0
elif [[ -n "${VALUE_n}" && "${VALUE_n}" =~ ^[0-9]+$  ]]; then
  DP=${VALUE_n}
else 
  echo -e "[ERROR] ${VALUE_n} is not number"
  exit 1
fi

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

A maximum read count of remove        [ ${DP} ]
Output taxonomy count table:          [ ${OTT} ]
Output removed taxonomy table:        [ ${RMT} ]
Output taxonomy ASV sequence table:   [ ${OTF} ]
Output removed ASV sequence table:    [ ${RMF} ]
Output count table summarized by rank [ ${OUTCNT} ]

EOS

# 5. qiime2パイプライン実行 
#  5.1. qiime2起動
source ${CENV}
if echo ${CENV} | grep -q "anaconda" ; then 
 source activate ${QENV}
else 
 conda activate ${QENV} 
fi

# 5.2. 関数定義 
## 5.2.1 関数定義, ASVテーブルとtaxonomyデータとASV配列を結合(ヘッダー行有り)
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
## 5.2.2 関数定義, taxonomyデータとASV配列を結合(ヘッダー行有り)
function mtseq () {
    TTAX=$1; TSEQ=$2; 
    # taxonomyデータからrankの配列を取り出す (7列もしくは8列の場合がある)
    RANK=(`cut -f2 $TTAX | awk -F"; " '{if(NF==8){ \
    sub("_.*","",$1);sub("_.*","",$2);sub("_.*","",$3);sub("_.*","",$4); \
    sub("_.*","",$5); sub("_.*","",$6);sub("_.*","",$7); sub("_.*","",$8); \
    print $1" "$2" "$3" "$4" "$5" "$6" "$7" "$8;} \
    else if(NF==7){sub("_.*","",$1);sub("_.*","",$2);sub("_.*","",$3);sub("_.*","",$4); \
    sub("_.*","",$5); sub("_.*","",$6);sub("_.*","",$7); print $1" "$2" "$3" "$4" "$5" "$6" "$7;}}' | head -1`)
    HDC=(`echo ASV_ID confidence ${RANK[@]} Seq`)

    # idの同一性チェック
    id_tax=(`grep -v "^Feature" ${TTAX} | awk -F"\t" '{print $1}'`)
    id_seq=(`grep "^>" ${TSEQ} | sed 's/^>//'`)
    un=(`echo ${id_tax[*]} ${id_seq[*]} | tr ' ' '\n' | sort | uniq -c | awk '{print $1 }' | uniq`)

    if [[ ${#un[@]} == 1 && ${un[@]} == 2 ]]; then
        echo ${HDC[@]} | tr ' ' '\t'
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
TEMP_TAX=$(mktemp -d)
trap 'rm -rf $TEMP_TAX' EXIT
unzip -q ${TAX} -d $TEMP_TAX
TAXTSV="${TEMP_TAX}/*/data/taxonomy.tsv"

if [[ ! -f $(echo $TAXTSV) ]] ; then 
    echo -e "[ERROR] The specified argument ${TAX} may not be a taxonomy."
    exit 1 
else 
    echo -e "[INFO] The taxonomy data unzipped to temporary directory.  ${TAXTSV}"
fi

## 5.3.2 ASVテーブルを展開 ${BIOME}
if [[ -n "${TAB}" ]]; then
    TEMP_TAB=$(mktemp -d)
    trap 'rm -rf ${TEMP_TAB}' EXIT
    unzip -q ${TAB} -d ${TEMP_TAB}
    BIOME="${TEMP_TAB}/*/data/feature-table.biom" 
    if [[ ! -f $(echo ${BIOME}) ]] ; then
        echo -e "[ERROR] ${TAB} may not be a feature table. "
        exit 1
    else 
        echo -e "[INFO] The feature table data unzipped to temporary directory.  ${BIOME}"
    fi
fi
## 5.3.3 ASV配列の展開 ${ASVFA}
if [[ -n "${SEQ}" ]]; then
    TEMP_SEQ=$(mktemp -d)
    trap 'rm -rf ${TEMP_SEQ}' EXIT
    unzip -q ${SEQ} -d ${TEMP_SEQ} 
    ASVFA="${TEMP_SEQ}/*/data/dna-sequences.fasta"

    if [[ ! -f $(echo ${ASVFA}) ]] ; then
        echo -e "[ERROR] ${SEQ} may not be a ASV fasta. "
        exit 1
    else 
        echo -e "[INFO] The ASV fasta unzipped to temporary directory.  ${ASVFA}"    
    fi

fi

# 5.4. データを結合
## ASV_IDの対応表を作成
cut -f1 ${TAXTSV} | awk 'NR>1{print $1"\t" "OTU" NR-1}' > asv_correspo.tsv
ls asv_correspo.tsv > /dev/null 2>&1 || { echo -e "[ERROR] There is not ASV_ID correspondign table." ; }

## 一時ファイルを格納するディレクトリ(5.4 及び　5.5で使うファイルはここに格納)
temp_cnt=$(mktemp -d)
trap 'rm -rf $temp_cnt' EXIT

## taxonomyとASVテーブル及びASV配列の結合 
## NOTE: この部分は関数にするmtaxと結合　taxonomy, feature-table, DP, pick.table, rm.table
if [[ -f $(echo ${ASVFA}) && -f $(echo ${BIOME}) ]] ; then
    ## taxonomyデータとfeature-tableの結合 (一時ファイルに書き出し)、リード数でフィルタ(filter_featureの代替)
    biom convert -i ${BIOME} -o ./feature-table.tsv --to-tsv 
    mtax ${TAXTSV} feature-table.tsv > ${temp_cnt}/tmp_taxtsv
    HDC=($(head -1 ${temp_cnt}/tmp_taxtsv))
    echo ${HDC[@]} | tr ' ' '\t' > ${temp_cnt}/${OTT}
    awk -F"\t" 'NR==FNR{a[$1]=$2}NR!=FNR{if ($1 in a) {print a[$1]"\t"$0 } }' asv_correspo.tsv ${temp_cnt}/tmp_taxtsv \
    | cut -f1,3- | sort -t$'\t' -V -k1,1 >> ${temp_cnt}/${OTT}

    ## リード数でフィルタ(filter_featureの代替)
    if [[ ${DP} > 1 ]]; then
      ## 最大リード数以下のOTUのIDを取得(ヘッダ行があることに注意)
      PICKOTU=($(cut -f1,10- ${temp_cnt}/${OTT} \
      | awk -F"\t" -v DP=${DP} 'NR>1{for(i=2;i<=NF;i++){if(max[NR]==0){max[NR]=$i}else if(max[NR]<$i){max[NR]=$i}};if( max[NR]>DP)print $1;}' ))
      ## フィルターパスしたカウントテーブルと除去したカウントテーブルを別々に保存
      awk 'NR==FNR{a[$1]=$1}NR!=FNR{if ($1 in a) print > "'${temp_cnt}/pick_otu.txt'"; else print > "'${temp_cnt}/rm_otu.txt'" }' \
        <( echo ${PICKOTU[@]}|tr ' ' '\n' ) \
        <( awk -F"\t" 'NR>1' ${temp_cnt}/${OTT} )
      ## カレントディレクトリにヘッダ行を追記して書き出し
      head -1 ${temp_cnt}/${OTT} > ${OTT}
      cat "${temp_cnt}/pick_otu.txt" >> ${OTT}
      head -1 ${temp_cnt}/${OTT} > removed_otu.tsv
      cat "${temp_cnt}/rm_otu.txt" >> removed_otu.tsv
    else
      cp ${temp_cnt}/${OTT} ./${OTT}
    fi

    ## taxonomyデータとASV-fastaの結合  
    mtseq ${TAXTSV} ${ASVFA} > ${temp_cnt}/tmp_taxseq
    HDT=($(head -1 ${temp_cnt}/tmp_taxseq))
    echo ${HDT[@]} | tr ' ' '\t' > ${temp_cnt}/${OTF}
    awk -F"\t" 'NR==FNR{a[$1]=$2}NR!=FNR{if ($1 in a) {print a[$1]"\t"$0 } }' asv_correspo.tsv ${temp_cnt}/tmp_taxseq \
    | cut -f1,3- | sort -t$'\t' -V -k1,1 >> ${temp_cnt}/${OTF} 

    ## Removed OTU-table & Picked OTU-table (カレントディレクトリに書き出し)
    if [[ ${DP} > 1 ]]; then
        PICKOTU=($(cut -f1,10- ${temp_cnt}/${OTT} \
        | awk -F"\t" -v DP=${DP} 'NR>1{for(i=2;i<=NF;i++){if(max[NR]==0){max[NR]=$i}else if(max[NR]<$i){max[NR]=$i}};if( max[NR]>DP)print $1;}' ))
        awk 'NR==FNR{a[$1]=$1}NR!=FNR{if ($1 in a) print > "'${temp_cnt}/pick_otu.txt'"; else print > "'${temp_cnt}/rm_otu.txt'" }' \
        <( echo ${PICKOTU[@]}|tr ' ' '\n' ) \
        <( awk -F"\t" 'NR>1' ${temp_cnt}/${OTT} )

        awk 'NR==FNR{a[$1]=$1}NR!=FNR{if ($1 in a) print > "'${temp_cnt}/pick_asv.txt'"; else print > "'${temp_cnt}/rm_asv.txt'"}' \
        <( echo ${PICKOTU[@]}|tr ' ' '\n' ) \
        <( awk -F"\t" 'NR>1' ${temp_cnt}/${OTF} ) 

        head -1 ${temp_cnt}/${OTT} > ${OTT}
        cat "${temp_cnt}/pick_otu.txt" >> ${OTT}
        head -1 ${temp_cnt}/${OTT} > removed_otu.tsv
        cat "${temp_cnt}/rm_otu.txt" >> removed_otu.tsv

        head -1 ${temp_cnt}/${OTF} > ${OTF}
        cat "${temp_cnt}/pick_asv.txt" >> ${OTF}
        head -1 ${temp_cnt}/${OTF} > removed_asv.txt
        cat "${temp_cnt}/rm_asv.txt" >> removed_asv.txt
    else
      cp ${temp_cnt}/${OTF} ./${OTF}
    fi

# elif [[ -f $(echo ${BIOME}) ]]; then
#     ## taxonomyデータとfeature-tableを結合
#     biom convert -i ${BIOME} -o ./feature-table.tsv --to-tsv 
#     mtax ${TAXTSV} feature-table.tsv \
#     | awk -F"\t" 'NR==FNR{a[$1]=$2}NR!=FNR{if ($1 in a) {print a[$1]"\t"$0 } }' asv_correspo.tsv - \
#     | cut -f1,3- | sort -t$'\t' -V -k1,1 > ${OTT}
#     #mtax ${TAXTSV} feature-table.tsv > ${OTT}

# elif [[ -f $(echo ${ASVFA}) ]]; then
#     ## taxonomyデータとASV配列を結合
#     mtseq ${TAXTSV} ${ASVFA} \
#     | awk -F"\t" 'NR==FNR{a[$1]=$2}NR!=FNR{if ($1 in a) {print a[$1]"\t"$0 } }' asv_correspo.tsv - \
#     | cut -f1,3- | sort -t$'\t' -V -k1,1 > ${OTF} 
#     #mtseq ${TAXTSV} ${ASVFA} > ${OTF}
else 
    echo -e "[ERROR] The ${ASVFA} and ${BIOME} does not exists. "
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
  out=${OUTCNT}/count_${abr[$k]}.tsv

 for x in ${smps[@]}; do 
  cat ${in} | awk -F"\t" -v x=${x} '$2==x{print $1"\t"$3}' \
  | sort -t$'\t' -k1,1 > ${temp_cnt}/${rnk}_${x}.tmp
 done
 
n_temp=`ls ${temp_cnt}/*.tmp | wc -l` # sample numbers
slct=(`seq 2 2 $((${n_temp}*2))`) # column numbers of count data only
echo -e "taxon "${smps[*]} | tr ' ' '\t' > ${out}
paste ${temp_cnt}/${rnk}*.tmp | cut -f1,`echo ${slct[@]}|tr ' ' ','`  >> ${out}

done

# 5.6. 一時ファイルの移動, 削除
if [[ -f feature-table.tsv ]];then rm feature-table.tsv; fi