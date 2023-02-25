#!/bin/bash
VERSION=0.1.230217
AUTHOR=SHOGO_KONISHI
CMDNAME=`basename $0`

# ヘルプの表示
function print_doc() {
cat << EOS
使用法:
    $CMDNAME [オプション] <taxonomy.qza> 

用語の定義およびこのプログラム中で使用されるデフォルトファイル名:
    ASV配列     Denoisingされた配列 [repset.qza]
    ASVテーブル  検体に含まれるASVのリードカウントテーブル. qiime2的にはfeaturetable [table.qza]
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
# 使用法の表示
function print_usg() {
cat << EOS
使用例: 
    $CMDNAME -t table.qza taxonomy.qza      # ASVテーブルとtaxonomyの結合      
    $CMDNAME -s repset.qza taxonomy.qza     # ASV配列とtaxonomyの結合 & ASV-tree構築
    $CMDNAME -t table.qza -s repset.qza taxonomy.qza # 上記2つを実行
    $CMDNAME -t table.qza -s repset.qza -u taxonomy.qza # ASV-treeからUnassigned taxon除去

EOS
}

### 引数チェック ###
# 1-1. オプションの入力処理
# 1-2. conda環境変数ファイルの存在確認
# 1-3. qiime2環境の存在確認
# 1-4. コマンドライン引数の判定 
# 1-5. オプション引数の判定
#   1-5-1. ASV配列及の判定
#   1-5-2. ASVテーブルの判定
#   1-5-3. その他オプション引数の判定
# 1-6. プログラムに渡す引数の一覧
###

# 1-1. オプションの入力処理 
while getopts e:q:t:s:o:uh OPT
do
  case $OPT in
    "e" ) VALUE_e="$OPTARG";;
    "q" ) VALUE_q="$OPTARG";;

    "t" ) VALUE_t="$OPTARG";;    
    "s" ) VALUE_s="$OPTARG";;
    
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

# 1-2. conda環境変数ファイルの存在確認
if [[ -z "${VALUE_e}" ]]; then CENV="${HOME}/miniconda3/etc/profile.d/conda.sh"; else CENV=${VALUE_e}; fi
if [[ -f "${CENV}" ]]; then : ; else echo "[ERROR] The file for the conda environment variable cannot be found. ${CENV}"; exit 1; fi

# 1-3. qiime2環境の存在確認
if [[ -z "${VALUE_q}" ]]; then QENV="qiime2-2022.8"; else QENV=${VALUE_q}; fi
if conda info --envs | awk '!/^#/{print $1}'| grep -qx "^${QENV}$" ; then
    :
else 
    echo "[ERROR] The conda environment ${QENV} was not found."
    conda info --envs
    exit 1
fi

# 1-4. コマンドライン引数の判定 
if [[ $# = 1 ]]; then
    TAX=$1
    if [[ ! -f ${TAX} || ${TAX##*.} != 'qza' ]] ; then 
        echo "[ERROR] The taxonomy data ${TAX} does not exist or is not in qza format." ; exit 1
    fi   
else
    echo "[ERROR] 引数としてtaxonomyデータ(qza形式)が必要です。";  print_usg; exit 1
fi

# 1-5. オプション引数の判定
## 1-5-1. ASV配列及の判定
if [[ -z "${VALUE_s}" && -z "${VALUE_t}" ]]; then echo "[ERROR] Either or both options t/s must be selected."; exit 1 ; fi
if [[ -n "${VALUE_s}" ]]; then
    SEQ=${VALUE_s} # input
    OUTRE='exported_tree' # output
    OTF='taxonomy_asv.tsv' # output
    XTRE='taxtree.nwk' # output

    if [[ ! -f ${SEQ} || ${SEQ##*.} != 'qza' ]] ; then 
        echo "[ERROR] The ASV sequence, ${SEQ}, does not exist or is not in qza format." 
        exit 1
    fi
fi

## 1-5-2. ASVテーブルの判定
if [[ -n "${VALUE_t}" ]]; then
    TAB=${VALUE_t}
    if [[ ! -f ${TAB} || ${TAB##*.} != 'qza' ]] ; then 
        echo "[ERROR] The ASV table ${TAB} does not exist or is not in qza format." 
        exit 1
    fi
fi

## 1-5-3. その他オプション引数の判定 
if [[ -z "${VALUE_o}" ]]; then OTT="taxonomy_cnt.tsv"; else OTT=${VALUE_o}; fi
if [[ "${FLG_u}" = "TRUE" ]]; then UAT="TRUE" ; else UAT="FALSE" ; fi


if [[ -z "${VALUE_s}" ]] ; then 
    unset OUTRE ; unset OTF ; unset XTRE ; unset UAT 
elif [[ -z "${VALUE_t}" ]]; then
    unset OTT; 
fi

# 1-6. プログラムに渡す引数の一覧
cat << EOS >&2
### Merge taxonomy into count data, ASV sequences, and ASV trees ###
conda environmental values :        [ ${CENV} ]
qiime2 environment :                [ ${QENV} ]

The input taxonomy file path:       [ ${TAX}  ]
The input ASV table file path:      [ ${TAB}  ]
The input ASV file path:            [ ${SEQ}  ]

output taxonomy count table:        [ ${OTT}  ]
output taxonomy ASV sequence table: [ ${OTF}  ]
output directory for phylogeny:     [ ${OUTRE}  ]
output taxonomy tree:               [ ${XTRE} ]
Remove Unassigned taxon from tree:  [ ${UAT}  ]

EOS

### MAIN ###
# 2-1. qiime2起動
# 2-2. 関数定義
# 2-3. データを結合 qza形式のファイル(taxonomyデータ,ASVテーブル,ASV配列)をunzipしてテキストファイル取り出す。
#   2-3.1 taxonomyデータを抽出
#   2-3.2 taxonomyデータとASVテーブルを結合する。 
#   2-3.3 taxonomyデータとASV配列を結合する。
# 2-4. ASVの系統樹を作成
### 

# 2-1. qiime2起動
source ${CENV}
conda activate ${QENV}

# 2-2. 関数定義 
## 2-2.1 関数定義, ASVテーブルとtaxonomyデータとASV配列を結合する。 
function mtax () {
    TTAX=$1; TTAB=$2; TSEQ=$3; 
    # カウントデータからヘッダ行抽出
    HD=`grep "^#OTU ID" ${TTAB} | sed 's/^#OTU ID//'`
    if [[ -f ${TTAX} && -f ${TTAB} && -f ${TSEQ}  ]]; then
        HDC=(`echo "ASV_ID confidence domain phylum class order family genus species ${HD} sequence"`)
    elif [[ -f ${TTAX} && -f ${TTAB} && ! -f ${TSEQ} ]]; then
        HDC=(`echo "ASV_ID confidence domain phylum class order family genus species ${HD}" `)
    else
        echo "[ERROR]"
    fi

    # idの同一性チェック(taxonomyとASVテーブルをマージする場合)
    id_tab=(`grep -v "^#" ${TTAB} | awk -F"\t" '{print $1}'`)
    id_tax=(`grep -v "^Feature" ${TTAX} | awk -F"\t" '{print $1}'`)
    un1=(`echo ${id_tab[*]} ${id_tax[*]} | tr ' ' '\n' | sort | uniq -c | awk '{print $1 }' | uniq`) 
    
    # idの同一性チェック(taxonomyとASVテーブルとASV配列をマージする場合)
    if [[ -n ${TSEQ} ]]; then
        id_seq=(`grep "^>" dna-sequences.fasta | sed 's/^>//'`)
        un2=(`echo ${id_tab[*]} ${id_seq[*]} | tr ' ' '\n' | sort | uniq -c | awk '{print $1 }' | uniq`)
    fi

    # Merge
    if [[ -z ${TSEQ} && ${#un1[@]} == 1 && ${un1[@]} == 2 ]]; then
        echo ${HDC[@]} | tr ' ' '\t'
        paste <(cat ${TTAX} | awk -F"\t" 'NR>1{print $1"\t"$3}' | sort -k1,1 ) \
        <(cat ${TTAX} | awk -F"\t" 'NR>1{print $1"\t"$2}' | sort -k1,1 | awk -F"\t" '{print $2}'\
        | awk -F"; " '{print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7}') \
        <( awk 'NR>2{print}' ${TTAB} | sort -k1,1 | cut -f 2- ) 
    

    elif [[ -n ${TSEQ} && ${#un1[@]} == 1 && ${un1[@]} == 2 && ${#un2[@]} == 1 && ${un2[@]} == 2 ]]; then
        echo ${HDC[@]} | tr ' ' '\t'
        paste <(cat ${TTAX} | awk -F"\t" 'NR>1{print $1"\t"$3}' | sort -k1,1 ) \
        <(cat ${TTAX} | awk -F"\t" 'NR>1{print $1"\t"$2}' | sort -k1,1 | awk -F"\t" '{print $2}'\
        | awk -F"; " '{print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7}') \
        <( awk 'NR>2{print}' ${TTAB} | sort -k1,1 | cut -f 2-) \
        <( cat ${TSEQ} | awk 'BEGIN{RS=">"; FS="\n"} NR>1 {print $1"\t"$2;}' | sort -k1,1 | cut -f 2-)
    else 
        echo "[ERROR] The file format of inputs was invalid."
    fi
}
## 2-2.2 関数定義, taxonomyデータとASV配列を結合
function mtseq () {
    TTAX=$1; TSEQ=$2; 
    id_tax=(`grep -v "^Feature" ${TTAX} | awk -F"\t" '{print $1}'`)
    id_seq=(`grep "^>" dna-sequences.fasta | sed 's/^>//'`)
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
## 2-2.3 関数定義, taxonomyデータから最も上位のタクソンを抽出
function id_tax () {
    # $9:s, $8:g, $7:f, $6:o, $5:c, $4:p, $3:k
    cat $1 \
    | awk -F"\t" '{ sub("s__", "", $9); sub("g__","", $8); sub("f__","",$7); \
    sub("o__","",$6); sub("c__","",$5); sub("p__","",$4); sub("k__","",$3); \
    if ($9 !="") print $1 "\t" "s__"$8"_"$9 ; \
    else if ($9=="" && $8 !="") print $1 "\t" "g__"$8 ; \
    else if ($9=="" && $8=="" && $7 !="") print $1 "\t" "f__" $7 ; \
    else if ($9=="" && $8=="" && $7 =="" && $6 !="") print $1 "\t" "o__" $6 ; \
    else if ($9=="" && $8=="" && $7 =="" && $6 =="" && $5 !="" ) print $1 "\t" "c__" $5 ; \
    else if ($9=="" && $8=="" && $7 =="" && $6 =="" && $5 =="" && $4 !="" ) print $1 "\t" "p__" $4 ; \
    else if ($9=="" && $8=="" && $7 =="" && $6 =="" && $5 =="" && $4 =="" && $3 !="") print $1 "\t" "k__" $3 ; \
    else print $1 "\t" "Unassigned" }'
}

## 2-2.4 関数定義, fastaファイルから指定idを除外
function faGetrest (){
  id=(${1}); fa=$2; rest=$3
  cat ${fa} \
  | awk '/^>/ { print n $0; n = "" }!/^>/ { printf "%s", $0; n = "\n" } END{ printf "%s", n }' \
  | awk 'BEGIN{RS=">"; FS="\n"} NR>1 {print $1"\t"$2;}' \
  | awk 'NR==FNR{a[$1]=$1}NR!=FNR{if ($1 in a) ; else print ">"$1"\n"$2 > "'${rest}'"}' \
  <(echo ${id[@]} | tr ' ' '\n' ) -
}
# 2-3. データを結合
## taxonomyファイルの展開
unzip -q ${TAX} -d tmp
TAXTSV='tmp/*/data/taxonomy.tsv'
if [[ -f $(echo ${TAXTSV}) ]]; then
    mv ${TAXTSV} ./ ; rm -r ./tmp
else
    echo -e "[ERROR] The specified argument ${TAX} may not be a taxonomy."
    exit 1
fi

## ASVテーブルかつまたはASV配列の展開、及びとtaxonomyとの結合
if [[ -n "${TAB}" && -n "${SEQ}" ]]; then
    unzip -q ${TAB} -d tmp1 ; unzip -q ${SEQ} -d tmp2 
    BIOME='tmp1/*/data/feature-table.biom' ; ASVFA='tmp2/*/data/dna-sequences.fasta'

    if [[ -f $(echo ${ASVFA}) && -f $(echo ${BIOME}) ]] ; then
        biom convert -i ${BIOME} -o ./feature-table.tsv --to-tsv ; rm -r ./tmp1
        mtax taxonomy.tsv feature-table.tsv > ${OTT}

        mv ${ASVFA} ./ ; rm -r ./tmp2
        mtseq taxonomy.tsv dna-sequences.fasta > ${OTF} 

    else
        echo -e "[ERROR] ${SEQ} may not be an ASV sequence, and/or ${TAB} may not be a feature table. "
        exit 1
    fi

elif [[ -n "${TAB}" && -z "${SEQ}" ]]; then
    unzip -q ${TAB} -d tmp
    BIOME='tmp/*/data/feature-table.biom'
    if [[ -f $(echo ${BIOME}) ]]; then 
        biom convert -i ${BIOME} -o ./feature-table.tsv --to-tsv ; rm -r ./tmp
        mtax taxonomy.tsv feature-table.tsv> ${OTT}
    else 
        echo -e "[ERROR] The  ${TAB} may not be a feature table. "
        exit 1
    fi

elif [[ -z "${TAB}" && -n "${SEQ}" ]] ; then
    unzip -q ${SEQ} -d tmp
    ASVFA='tmp/*/data/dna-sequences.fasta'
    if [[ -f $(echo ${ASVFA}) ]]; then 
        mv ${ASVFA} ./ ; rm -r ./tmp
        mtseq taxonomy.tsv dna-sequences.fasta > ${OTF}
    else 
        echo -e "[ERROR] The ${SEQ} may not be an ASV sequence. "
        exit 1
    fi

else
    echo -e "[ERROR] "
fi

# 2-4. ASVの系統樹を作成
if [[ -f ${SEQ} ]] ; then
    ## 4-1. ASV配列からUnassignedを除去, 除去したfastaをインポート 
    if [[ $UAT = "TRUE" ]]; then
        unid=(`cat taxonomy.tsv | awk -F"\t" '$2~/Unassigned/{print $1}'`)
        if [[ "${#unid[@]}" > 0 ]]; then 
            faGetrest "${unid[*]}" dna-sequences.fasta dna-sequences_ast.fasta
            qiime tools import --input-path dna-sequences_ast.fasta --output-path repset_tmp.qza --type 'FeatureData[Sequence]'
        else 
            qiime tools import --input-path dna-sequences.fasta --output-path repset_tmp.qza --type 'FeatureData[Sequence]'
        fi
    else 
        cp ${SEQ} repset_tmp.qza
    fi
  
    ## 出力ディレクトリを確認
    OUTRE='exported_tree'
    if [[ -d "${OUTRE}" ]]; then
        echo "[WARNING] ${OUTRE} was already exists. The output files may be overwritten."
    else 
        mkdir "${OUTRE}"
    fi

    ## 4-2. マルチプルアラインメント
    qiime alignment mafft --i-sequences repset_tmp.qza --o-alignment aligned-repset.qza
    if [[ ! -f aligned-repset.qza ]] ; then echo "[ERROR] Failed multiple alignment" ; exit 1 ; fi
    ## 4-3. アライメントのマスク
    qiime alignment mask --i-alignment aligned-repset.qza --o-masked-alignment masked-aligned-repset.qza
    ## 4-4. 無根系統樹作成
    qiime phylogeny fasttree --i-alignment masked-aligned-repset.qza --o-tree unrooted-tree.qza
    ## 4-5. midpoint root 
    qiime phylogeny midpoint-root --i-tree unrooted-tree.qza --o-rooted-tree rooted-tree.qza
    ## 4-6. export tree as newick format
    qiime tools export --input-path rooted-tree.qza --output-path ${OUTRE}
    TRE="${OUTRE}/tree.nwk"

    ## 4-7. newick-treeの編集。
    id_tax ${OTF} \
    | awk -F"\t" 'NR==FNR{arr[$1]=$2;} \
    NR!=FNR{for (i in arr){gsub(i, arr[i])};  print; }' - ${TRE} > ${XTRE}

fi

# 2-5. 一時ファイルの移動, 削除
mv aligned-repset.qza masked-aligned-repset.qza unrooted-tree.qza rooted-tree.qza ${OUTRE}
if [[ -f feature-table.tsv ]];then rm feature-table.tsv; fi
if [[ -f dna-sequences.fasta ]];then rm dna-sequences.fasta; fi
if [[ -f taxonomy.tsv ]];then rm taxonomy.tsv ; fi
if [[ -f repset_tmp.qza ]];then rm repset_tmp.qza; fi
