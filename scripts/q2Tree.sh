#!/bin/bash
VERSION=0.0.231124
AUTHOR=SHOGO_KONISHI
CMDNAME=$(basename $0)

### Contents: Run qiime2 pipeline  ###
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
    feature-table  検体に含まれるASVのリードカウントテーブル. qiime2的にはfeature-table [table.qza]
    taxonomy    ASVの系統推定結果 qiime feature-classifierの出力 [taxonomy.qza]
    系統組成表   taxonomyデータとfeature-tableを結合したもの [taxonomy_cnt.tsv]

説明:
    このプログラムはqiime2が出力したASV配列とtaxonomyデータから、
    ノードラベルをtaxonomic-nameに変換したASV配列の系統樹を作成します。
    uオプションを指定することで、系統アサインされなかったASVは除去できます。
    qiime2の出力するnewick形式のASVツリーでは、各ノードがASVのハッシュ値となっているため
    taxonomyデータを基にしてnewickツリーのノードラベルをtaxonomic-nameに変換します。

    入力ファイルはコマンドライン引数にtaxonomyデータ[taxonomy.qza]を指定し、
    オプション引数としてASV配列[repset.qza]を指定してください。
    いずれもqza形式で指定します。編集されたnewickツリーは結合された出力ファイル[taxonomy_cnt.tsv|taxonomy_asv.tsv]として、
    tsv形式で書き出されます。

オプション: 
  -e    conda環境変数パス[default: ${HOME}/miniconda3/etc/profile.d/conda.sh ]
  -q    qiime2環境名[default: qiime2-2021.8 ]
  -s    ASV配列 [default: repset.qza]
  -o    出力ディレクトリ [default: exported_tree]
  -u    系統樹作成の際に、Unassignedタクソンを除外
  -h    ヘルプドキュメントの表示

使用例:   
    $CMDNAME -s repset.qza taxonomy.qza         # ASV-tree構築 
    $CMDNAME -s repset.qza -u taxonomy.qza      # ASV-treeからUnassigned taxonを除去

EOS
}

if [[ "$#" = 0 ]]; then print_doc ; exit 1; fi

# 2. オプション引数の処理
#  2.1. オプション引数の入力
while getopts e:q:s:o:uh OPT
do
  case $OPT in
    "e" ) CENV="$OPTARG";;
    "q" ) QENV="$OPTARG";;
    "s" ) SEQ="$OPTARG";;
    "o" ) OTRE="$OPTARG";;
    "u" ) FLG_u="TRUE" ;;
    "h" ) print_doc ; exit 1 ;; 
    *) print_doc ; exit 1;; 
    \? ) print_doc ; exit 1 ;;
  esac
done
shift $(expr $OPTIND - 1)

#  2.2. オプション引数の判定およびデフォルト値の指定
## conda環境変数ファイルの存在確認
if [[ -z "${CENV}" ]]; then CENV="${HOME}/miniconda3/etc/profile.d/conda.sh"; fi
if [[ ! -f "${CENV}" ]]; then
 echo "[ERROR] The file for the conda environment variable cannot be found. ${CENV}"
 exit 1
fi
## qiime2環境の存在確認
if [[ -z "${QENV}" ]]; then QENV="qiime2-2022.2"; fi
if conda info --envs | awk '!/^#/{print $1}'| grep -q "^${QENV}$" ; then
    :
else 
    echo "[ERROR] The conda environment ${QENV} was not found."
    conda info --envs
    exit 1
fi
## ASV配列の判定
if [[ -z "${SEQ}" ]]; then echo "[ERROR] The options [-s] must be required."; exit 1 ; fi
if [[ ! -f ${SEQ} || ${SEQ##*.} != 'qza' ]] ; then 
  echo "[ERROR] The ASV sequence, ${SEQ}, does not exist or is not in qza format." 
  exit 1
fi

## 出力ファイル名
## その他オプション引数の判定 
if [[ -z "${OTRE}" ]]; then OTRE='exported_tree'; else : ; fi
XTRE="${OTRE}/taxonomy.nwk"
if [[ "${FLG_u}" = "TRUE" ]]; then UAT="TRUE" ; else UAT="FALSE" ; fi


# 3. コマンドライン引数の処理 
if [[ $# = 1 ]]; then 
  TAX=$1
  if [[ ! -f ${TAX} || ${TAX##*.} != 'qza' ]] ; then 
    echo "[ERROR] The taxonomy data ${TAX} does not exist or is not in qza format." ; exit 1
  fi   
else 
  echo "[ERROR] 引数としてtaxonomyデータ(qza形式)が必要です。"
  exit 1
fi

# 4. プログラムに渡す引数の一覧
cat << EOS >&2

### Create phylogenetic tree from ASV sequences ###
conda environmental values :        [ ${CENV} ]
qiime2 environment :                [ ${QENV} ]
The input taxonomy file path:       [ ${TAX} ]
The input ASV file path:            [ ${SEQ} ]
output directory for phylogeny:     [ ${OTRE} ]
output taxonomy tree:               [ ${XTRE} ]
Remove Unassigned taxon from tree:  [ ${UAT} ]

EOS

# 5. qiime2パイプライン実行 
#  5.1. qiime2起動
source ${CENV}
if echo ${CENV} | grep -q "anaconda" ; then source activate ${QENV}; else conda activate ${QENV}; fi

# 5.2. 関数定義 
## 5.2.1 関数定義, feature-tableとtaxonomyデータとASV配列を結合
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

    # idの同一性チェック(taxonomyとfeature-tableをマージする場合)
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
## 5.3.1 taxonomyファイルの展開 ${TAXTSV}, ASV配列一時ディレクトリに展開 ${ASVFA}
temp_tax=$(mktemp -d)
temp_seq=$(mktemp -d)
trap 'rm -rf ${temp_seq} ${temp_tax}' EXIT
unzip -q ${SEQ} -d ${temp_seq} 
unzip -q ${TAX} -d $temp_tax
ASVFA="${temp_seq}/*/data/dna-sequences.fasta"
TAXTSV="${temp_tax}/*/data/taxonomy.tsv"

if [[ ! -f $(echo $TAXTSV) ]] ; then 
    echo -e "[ERROR] The specified argument ${TAX} may not be a taxonomy."
    exit 1 
else 
  echo -e "[INFO] The taxonomy data unzipped to temporary directory.  ${TAXTSV}"
fi
  
if [[ ! -f $(echo ${ASVFA}) ]] ; then
  echo -e "[ERROR] ${SEQ} may not be a ASV fasta. "
  exit 1
else 
  echo -e "[INFO] The repset data unzipped to temporary directory.  ${ASVFA}"
fi


# 5.4. ASVの系統樹を作成
## 5.4.1. ASV配列からUnassignedを除去, 除去したfastaを再びインポート 
repset_tmp=${temp_seq}/repset_tmp.qza
if [[ $UAT = "TRUE" ]]; then
    unid=(`cat ${TAXTSV} | awk -F"\t" '$2~/Unassigned/{print $1}'`)

    if [[ "${#unid[@]}" > 0 ]]; then 
        echo -e "[INFO] Remove unassigned ASV"
        echo -e "${unid[@]}" | tr ' ' '\n'
        faGetrest "${unid[*]}" ${ASVFA} dna-sequences_ast.fasta
        qiime tools import --input-path dna-sequences_ast.fasta --output-path ${repset_tmp} --type 'FeatureData[Sequence]'
        echo -e "[INFO] The modified repset created at temporary directory.  ${repset_tmp}"
    else 
        echo "# Unassigne ASV does not exist."
        qiime tools import --input-path ${ASVFA} --output-path ${repset_tmp} --type 'FeatureData[Sequence]'
        echo -e "[INFO] The modified repset created at temporary directory.  ${repset_tmp}"
    fi
else
    echo  
    cp ${SEQ} ${repset_tmp}
fi

## 出力ディレクトリを確認
if [[ -d "${OTRE}" ]]; then
    echo "[WARNING] ${OTRE} was already exists. The output files may be overwritten." >&2
else 
    mkdir "${OTRE}"
fi

# qiime phylogeny align-to-tree-mafft-fasttree \
#   --i-sequences ${repset_tmp} \
#   --o-alignment aligned-repset.qza \
#   --o-masked-alignment masked-aligned-repset.qza \
#   --o-tree unrooted-tree.qza \
#   --o-rooted-tree rooted-tree.qza \
#   --p-n-threads auto

## 4-2. マルチプルアラインメント
qiime alignment mafft --i-sequences ${repset_tmp} --o-alignment aligned-repset.qza
if [[ ! -f aligned-repset.qza ]] ; then echo "[ERROR] Failed multiple alignment" ; exit 1 ; fi

## 4-3. アライメントのマスク
qiime alignment mask --i-alignment aligned-repset.qza --o-masked-alignment masked-aligned-repset.qza

## 4-4. 無根系統樹作成
qiime phylogeny fasttree --i-alignment masked-aligned-repset.qza --o-tree unrooted-tree.qza

## 4-5. Midpoint root 
qiime phylogeny midpoint-root --i-tree unrooted-tree.qza --o-rooted-tree rooted-tree.qza

## 4-6. Export tree as newick format and modify nodes of the tree.
qiime tools export --input-path rooted-tree.qza --output-path ${OTRE}

## 4-7. Modify nodes of the newick tree.
TRE="${OTRE}/tree.nwk"
id_tax ${TAXTSV} \
| awk -F"\t" 'NR==FNR{arr[$1]=$2;} NR!=FNR{for (i in arr){gsub(i":", arr[i]":")};  print; }' - ${TRE} > ${XTRE}

# # 5.6. 一時ファイルの移動
mv aligned-repset.qza masked-aligned-repset.qza unrooted-tree.qza rooted-tree.qza ${OTRE}

