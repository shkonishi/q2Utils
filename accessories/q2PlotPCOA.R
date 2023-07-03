# 1. 引数処理
# 2. 引数チェック
#  2.1. 入力ディレクトリ存在確認
#  2.2. 入力ファイル(qza)存在確認
#  2.3. 出力ディレクトリ存在確認
# 3. データ読み込み
#  3.1. qza ファイル展開
#  3.2. alpha-diversityデータの読み込み
#  3.3. metadata読み込み & alpha-diversityデータと結合
#  3.2. PCoAファイルパスの入力
#  3.5. PCoA sore及び寄与率データを読み込み
#  # 関数定義: PCoA soreのdfを読み込み
#  # 関数定義: 寄与率データ読み込み
#  # PCoA スコアを読み込み、メタデータを結合したDfを作成
#  # 寄与率データ読み込み、寄与率軸ラベルのリストを作成
# 4. PCoA結果のプロット
#  4.1. ggplotオブジェクトのリスト
#  4.2. All PCoA plot saved in PDF

# NOTE: プロットにテキストラベル
# NOTE: ggsave(obj, width=7, height=7, units="in")

# 1. 引数処理
argv <- commandArgs(TRUE)
in_d <- argv[1] # qza directory
in_m <- argv[2] # metadata file path

# 2. 引数チェック
## 2.1. 入力ディレクトリ存在確認
stopifnot("[STOP] There is not input directory." = dir.exists(in_d))
dir_qza <- basename(in_d)

## 2.2. 入力ファイル(qza)存在確認
in_upcoa <- paste(dir_qza, "unweighted_unifrac_pcoa_results.qza", sep="/")
in_wpcoa <- paste(dir_qza, "weighted_unifrac_pcoa_results.qza", sep="/")
in_bpcoa <- paste(dir_qza, "bray_curtis_pcoa_results.qza", sep="/")
in_sh <- paste(dir_qza, "shannon_vector.qza", sep="/")
in_ch1 <- paste(dir_qza, "chao1_vector.qza", sep="/")
in_sm <- paste(dir_qza, "simpson_vector.qza", sep="/")

input = c(in_upcoa, in_wpcoa, in_bpcoa, in_sh, in_ch1, in_sm, in_m)
(file_exist <- stack(sapply(input, file.exists)))
stopifnot("[STOP] Theres are not input files." = all(file_exist$values))

## 2.3. 出力ディレクトリ存在確認
out_d <- "./diversity_pdf"
stopifnot("[STOP] The output directory aleady exists." = !dir.exists(out_d))
dir.create(out_d)

# 3. データ読み込み
#  3.1. qza ファイル展開
unzip(in_upcoa, exdir = "out_upcoa")
unzip(in_wpcoa, exdir = "out_wpcoa")
unzip(in_bpcoa, exdir = "out_bpcoa")
unzip(in_sh, exdir = "out_sh")
unzip(in_ch1, exdir = "out_ch1")
unzip(in_sm, exdir = "out_sm")

#  3.2. alpha-diversityデータの読み込み
print("## Import alpha-diversity")
in_vshn <- paste0(list.files("./out_sh", full.names = T), "/data/alpha-diversity.tsv")
in_vch1 <- paste0(list.files("./out_ch1", full.names = T), "/data/alpha-diversity.tsv")
in_vsmp <- paste0(list.files("./out_sm", full.names = T), "/data/alpha-diversity.tsv")
vshn <- read.table(in_vshn, T, "\t", comment.char = "")
vch1 <- read.table(in_vch1, T, "\t", comment.char = "")
vsmp <- read.table(in_vsmp, T, "\t", comment.char = "")

#  3.3. metadata読み込み & alpha多様性データの結合
print("## Merge metadata with alpha diversity")
meta <- meta <- read.table(in_m, T, "\t", comment.char = "", check.names = F)
names(meta)[1] <- "SampleID"
dat_adiv <- cbind(meta,
                  shannon = vshn$shannon_entropy,
                  chao1 = vch1$chao1, 
                  simpson = vsmp$simpson)

#  3.4. PCoAファイルの読み込み
in_upco <- paste0(list.files("./out_upcoa", full.names = T), "/data/ordination.txt")
in_wpco <- paste0(list.files("./out_wpcoa", full.names = T), "/data/ordination.txt")
in_bpco <- paste0(list.files("./out_bpcoa", full.names = T), "/data/ordination.txt")

### 関数定義: PCoA soreのdfを読み込み
extLines <- function(in_f, st = "^Site\t"){
  x <- readLines(in_f)
  i1 <- grep(st, x)+1
  i2 <- which(!nzchar(x))
  i3 <- i2[i2>i1][1]-1
  pfx <- "PCo" # pfx <- "NMDS"
  dat <- data.frame(Reduce(rbind, strsplit(x[i1:i3], "\t")),row.names = NULL)
  dat[-1] <- apply(dat[-1], 2, as.numeric)
  setNames(dat, c("SampleID", paste0(pfx, seq(ncol(dat)-1))))
}
### 関数定義: 寄与率データ読み込み
extCntrb <- function(in_f, st = "^Proportion explained"){
  x <- readLines(in_f)
  i1 <- grep(st, x)+1
  i2 <- which(!nzchar(x))
  i3 <- i2[i2>i1][1]-1
  
  n1 <- unlist(strsplit(x[i1:i3], "\t"))[1]
  n2 <- unlist(strsplit(x[i1:i3], "\t"))[2]
  as.numeric(c(n1, n2))
}

### PCoA スコアを読み込み、メタデータを結合したDfを作成
print("## Merge NMDS score with metadata ")
in_pcos <- c(in_upco, in_wpco, in_bpco)
distms <- c("unweighted_unifrac", "weighted_unifrac", "bray_curtis")
dat_pcou <- lapply(seq_along(in_pcos), function(i){
  pco_score <- extLines(in_pcos[i])
  distm <- distms[i]
  merge(dat_adiv, pco_score[1:3], by = "SampleID")
})
dat_pcou <- setNames(dat_pcou, c("uuni","wuni","bray"))


### 寄与率データ読み込み、寄与率軸ラベルのリストを作成
pfx <- "PCo" # pfx <- "NMDS"
dat_cntrb <- lapply(seq_along(in_pcos), function(i){
  pco_cntrb <- extCntrb(in_pcos[i])
  xlb <- paste(paste0(pfx, "1: "), round(100 * pco_cntrb[1]), "%")
  ylb <- paste(paste0(pfx, "2: "), round(100 * pco_cntrb[2]), "%")
  c(xlb, ylb)
})

# 4. PCoA結果のプロット
#  4.1. ggplotオブジェクトのリスト
stp <- names(meta)[-1]
mt <- c("unweighted unifrac", "weighted unifrac", "bray-curtis")
adiv<- c("shannon","chao1","simpson")

suppressMessages(library(ggplot2))
ggobjs <- lapply(stp, function(x){
  st <- x
  lapply(seq_along(dat_pcou), function(i){
    dat <- dat_pcou[[i]]
    xlb <- dat_cntrb[[i]][1]
    ylb <- dat_cntrb[[i]][2]
    main <- mt[i]
    xax <- paste0(pfx,"1")
    yax <- paste0(pfx,"2")
  
    gg_sh <- ggplot(dat, aes(x=.data[[xax]], y=.data[[yax]], colour=.data[[st]])) +
      geom_point(aes(size=shannon), alpha=0.7) +
      xlab(xlb) +
      ylab(ylb) +
      theme_bw() +
      labs(colour=x, aes(size=shannon), title = main)
    gg_ch <- ggplot(dat, aes(x=.data[[xax]], y=.data[[yax]], colour=.data[[st]])) +
      geom_point(aes(size=chao1), alpha=0.7) +
      xlab(xlb) +
      ylab(ylb) +
      theme_bw() +
      labs(colour=x, aes(size=chao1), title = main)
    gg_sm <- ggplot(dat, aes(x=.data[[xax]], y=.data[[yax]], colour=.data[[st]])) +
      geom_point(aes(size=simpson), alpha=0.7) +
      xlab(xlb) +
      ylab(ylb) +
      theme_bw() +
      labs(colour=x, aes(size=simpson), title = main)
    list(gg_sh, gg_ch, gg_sm)
    })
})

#  4.2. Merged PCoA plot with patchwork
if("patchwork" %in% rownames(installed.packages()) ) {
    print("## Merged PCoA plot using patchwork saved in PDF")
    tmp <- vector("list", length = 3)
    for(i in seq_along(stp)){
        tmp[[i]] <- patchwork::wrap_plots(c(ggobjs[[i]][[1]], ggobjs[[i]][[2]], ggobjs[[i]][[3]]), nrow=3 )
        v <- paste0(out_d, "/", "PCoA_", stp[i], ".pdf")
        ggsave(v, tmp[[i]], width = 14, height = 9, units = "in")
    }
} 

# 4.3. All PCoA plot saved in PDF
print("## All PCoA plot saved in PDF")
ad<- c("shannon","chao1","simpson")
bd<- c("unweighted_unifrac","weighted_unifrac","bray_curtis")

for(i in seq_along(stp)){
    for(j in seq_along(bd)){
        for(k in seq_along(ad)){
            v <- paste0(out_d,"/", paste0(bd[j],"_", ad[k], "_", stp[i],".pdf"))
            ggsave(v, ggobjs[[i]][[j]][[k]], width = 8, height = 7, units = "in")
        
        }
    }
}

# 5. Remove temporary directory
unlink(out_sh, out_ch1, out_sm, out_upcoa,  out_wpcoa, out_bpcoa, recursive = TRUE)

# Rscriptの中でRmarkdownを呼び出す　# provided test.Rmd is in the working directory
# rmarkdown::render("test.Rmd")


