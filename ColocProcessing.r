## ------------------------------------------------------------------------
#TODO: Add support for fread and zipped textfiles
#TODO: Figure out the bug where there is an association but no intersection between SNPs
library(data.table)
library(optparse)
library(RColorBrewer)

option_list = list(
    make_option(c("-i", "--input"), type="character",
                help="The input RData file with coloc results generated by Colocolization.r"),
    make_option(c("-q", "--query"), type="character",
                help="Path to file containing paths to query files. Paths should be separated by a newline char."),
    make_option(c("-r", "--reference"), type="character",
                help="Path to file containing paths to reference files. Paths should be separated by a newline char."),
    make_option(c("-o", "--out"), type="character", default="./",
                help="Output file name.\n\t\t[default=./%default]"),
    make_option(c("-w", "--window"), type="numeric", default=250000,
                help="The window size used to extend the loci arround significant SNPs.\n\t\t[default=%default]"),
    make_option(c("-t", "--threshold"), type="numeric", default=0.5,
                help="The threshold for significant colocolization of ppH3 + ppH4.\n\t\t[default=%default]"),
    make_option(c("-s", "--suggestive"), type="numeric", default=5e-5,
                help="Threshold for suggestive line.\n\t\t[default=%default]"),
    make_option(c("-g", "--genomewide"), type="numeric", default=5e-8,
                help="Threshold for genome wide line.\n\t\t[default=%default]"),
    make_option(c("-n", "--colnamesquery"), type="character", default="rs,ps,chr,p_wald",
                help="Collumn names of: <snp id>,<posisiton>,<chromosome>,<pvalue> in query\n\t\t[default=%default]"),
    make_option(c("-p", "--colnamesreference"), type="character", default="rs,P",
                help="Collumn names of: <snp id>,<pvalue> in reference\n\t\t[default=%default]"),
    make_option(c("-f", "--fread"), action="store_true", default=FALSE,
                help="Use fread instead of read table to read the reference files.\n\t\t[default=%default]"),
    make_option(c("-z", "--zipped"), action="store_true", default=FALSE,
                help="Use are the refenence files zipped.\n\t\t[default=%default]")
)

opt_parser    <- OptionParser(option_list=option_list, description="\nScript for running the post proccessing of the coloc results. Generates a stacked manhattan plot for all loci of interest. ")
opt           <- parse_args(opt_parser)

tryCatch({
    load(opt$input)
    
    if (length(results) == 0) {
        cat(paste0("\n[ERROR]\tInput (colocolization.r output) contains no data. Exiting \n"))
        q(save="no")
    }
    
    qry.pathfile     <- opt$query
    qry.files        <- read.table(qry.pathfile, stringsAsFactors=F, header=F, sep=";")[,1]
    # TODO: make use of basename
    names(qry.files) <- sapply(qry.files, function(a){tail(strsplit(a, "/")[[1]], n=1)})

    ref.pathfile     <- opt$reference
    ref.files        <- read.table(ref.pathfile, stringsAsFactors=F, header=F, sep=";")[,1]
    names(ref.files) <- sapply(ref.files, function(a){tail(strsplit(a, "/")[[1]], n=1)})

    window           <- opt$window
    threshold        <- opt$threshold

    out.dir          <- opt$out
    if (!dir.exists(paste0(out.dir, "/coloc_plots/"))) {
        dir.create(paste0(out.dir, "/coloc_plots/"), recursive=T)
    }

    col.q            <- strsplit(opt$colnamesquery, ",")[[1]]
    col.r            <- strsplit(opt$colnamesreference, ",")[[1]]
}, warning=function(w){
    cat(paste0("\n[WARN]\t", w, "\n"))
},error=function(e){
    cat(paste0("\n[ERROR]\t", e, "\n"))
    print_help(opt_parser)
    q(save="no")
})

library(coloc)

## ------------------------------------------------------------------------
# Get the SNPs surrounding a significant loci for a given dataset
get.loci <- function(top.snp, query, window=250000, chr.col="chr", ps.col="ps", p.col="p_wald"){
    # Select all the SNPs within a certain window of the top SNPs
    loci <- lapply(top.snp, function(snp, snps, window, chr.col, ps.col, p.col){
        chr <- snps[snp, chr.col]
        pos <- snps[snp, ps.col]
        loci <- rownames(snps[snps[,chr.col] == chr,][snps[snps[,chr.col] == chr ,ps.col] > pos - window &
                                                      snps[snps[,chr.col] == chr ,ps.col] < pos + window,])
    }, snps=query, window=window, chr.col=chr.col, ps.col=ps.col, p.col=p.col)
    return(loci)
}


## ------------------------------------------------------------------------
# For loops for code readabillty and ease of use. Non critical for speed
for (mcQTL in names(results)) {
    if (!is.na(qry.files[mcQTL])) {
        qry           <- fread(qry.files[mcQTL], data.table=F, showProgress=F)
        rownames(qry) <- qry[,col.q[1]]
        
        for (locus.top in names(results[[mcQTL]])) {
            
            cat("[INFO]\tDetermining loci with coloc for:", mcQTL,"\n")
            cat("[INFO]\tTop SNP:", locus.top,"\n")
            locus  <- unlist(get.loci(locus.top, qry, window=window, chr.col=col.q[3], ps.col=col.q[2], p.col=col.q[4]))
            cat("[INFO]\tNumber of SNPs in locus:", length(locus),"\n")

            if (sum(is.na(locus)) > 0) {
                cat("[WARN]\tTop SNP not present in file. File might be incomplete.", mcQTL)
                next
            }
            # if (class(results[[mcQTL]][[locus.top]]) == "list") {
            #     cat("[WARN]\tNo results found for summary file. Probable reason: no overlapping snps. Skipping file")
            #    next
            #}
            assoc         <- t(data.frame(results[[mcQTL]][[locus.top]]))
            if (sum(dim(assoc)) == 0) {
                cat("[WARN]\tSkipping, result is empty\n")
                next
            }
            refs          <- na.omit(rownames(assoc)[(assoc[,5] + assoc[,6]) > threshold])
            
            # Save the data 
            write.table(qry[locus,], file=paste0(out.dir, "/coloc_plots/", locus.top, "_window", window, "_", mcQTL), quote=F)
            
            if (length(refs) > 0) {
                cat("[INFO]\tSignificant assoc using threshold: ", threshold, " in locus: ", locus.top, "\n")
                
                # Make the plots and define layout
                pdf(width=5, height=1.5*length(refs)+1.5, file=paste0(out.dir,"/coloc_plots/", locus.top, "_", mcQTL ,".pdf"))
                par(mar=c(1,4,4.5,2))
                layout(matrix(1:(length(refs)+1),nrow=length(refs)+1),
                       heights=c(1.5, rep(1, length(refs)-1), 1.5))
                par(cex=0.75)
                
                # Define the color pallete for the plots
                pallete <- colorRampPalette(brewer.pal(8, "Dark2"))(length(refs)+1)
                
                # Colour the non-significants with an alpha
                cols            <- qry[locus, col.q[4]] < opt$genomewide
                cols[cols]      <- pallete[1]
                cols[cols == F] <- adjustcolor(pallete[1], alpha.f=0.75)
                
                # Make the plot for the query summary stats
                plot(-log10(qry[locus, col.q[4]]) ~ qry[locus, col.q[2]],
                     pch=20,
                     main=gsub('(.{1,80})', '\\1\n', mcQTL),
                     ylab="-log10(p-value)",
                     xlab="",
                     cex=0.75,
                     cex.main=0.75,
                     xaxt="n",
                     ylim=c(0, max(-log10(qry[locus, col.q[4]]))+2),
                     xlim=c(min(qry[locus, col.q[2]]), max(qry[locus, col.q[2]])),
                     col=cols)
                
                # Add suggestive and genome wide lines
                abline(-log10(opt$suggestive), 0, col="blue")
                abline(-log10(opt$genomewide), 0, col="red")

                i.ref <- 1
                for (ref.file in refs) {
                    if (!is.na(ref.files[ref.file])) {
                        # Read the file as zipped or not
                        if (opt$zipped){
                            ref       <- fread(paste0("zcat < ", ref.files[ref.file]), data.table=F, header=T,stringsAsFactors=F, verbose=F, showProgress=F)
                        } else {
                            ref       <- fread(ref.files[ref.file], data.table=F, header=T, stringsAsFactors=F, verbose=F, showProgress=F)
                        }
                        ref           <- ref[!duplicated(ref[,col.r[1]]), ]
                        rownames(ref) <- ref[,col.r[1]]
                        i             <- intersect(rownames(ref), locus)
                        
                        if (length(i) == 0){
                          cat("[WARN]\tSkipping because no overlap between RS numbers\n")
                          next
                        }
                        cat("[DEBUG]\tProcessing file:", basename(ref.file),"\n")
                        cat("[DEBUG]\t", colnames(ref), "\n")

                        # Colour the non-significants with an alpha
                        cols            <- ref[i, col.r[2]] < opt$genomewide
                        cols[cols]      <- pallete[i.ref+1]
                        cols[cols == F] <- adjustcolor(pallete[i.ref+1], alpha.f=0.5)
                        
                        if (i.ref == length(refs)) {
                            par(mar=c(4.5,4,0,2))
                            plot(-log10(ref[i, col.r[2]]) ~ qry[i, col.q[2]],
                                 pch=20,
                                 ylim=c(0, max(-log10(ref[i, col.r[2]]))+2),
                                 xlim=c(min(qry[locus, col.q[2]]), max(qry[locus, col.q[2]])),
                                 ylab="-log10(p-value)",
                                 xlab=paste0("Position on ", qry[locus.top, col.q[3]]),
                                 cex=0.75,
                                 main="",
                                 col=cols)
                        } else {
                            par(mar=c(1,4,0,2))
                            plot(-log10(ref[i, col.r[2]]) ~ qry[i, col.q[2]],
                                 pch=20,
                                 ylim=c(0, max(-log10(ref[i, col.r[2]]))+2),
                                 xlim=c(min(qry[locus, col.q[2]]), max(qry[locus, col.q[2]])),
                                 ylab="-log10(p-value)",
                                 xaxt='n',
                                 xlab="",
                                 cex=0.75,
                                 main="",
                                 col=cols)  
                        }
                        
                        # Add suggestive and genome wide lines
                        abline(-log10(opt$suggestive), 0, col="blue")
                        abline(-log10(opt$genomewide), 0, col="red")
                        
                        i.ref <- i.ref + 1
                        # Add text annotation with coloc value
                        text(paste0(strtrim(ref.file, 25), "\nPP.H3 + PP.H4: ", round(assoc[ref.file, 5] + assoc[ref.file, 6], 2)),
                             cex=0.6,
                             y=max(-log10(ref[i, col.r[2]])),
                             x=max(qry[locus, col.q[2]]-50000)
                        )
                    } else {
                        #plot.new()
                        cat("[WARN]\tSkipping ref file because path is not availible for: ", ref.file, "\n")
                        next
                    }
                }
                dev.off()
            } else {
                cat("[INFO]\tNo significant assoc using threshold: ", threshold, " in locus: ", locus.top, "\n")
            }
        }
    } else {
        cat("[WARN]\tSkipping qry file because path is not availible for: ", mcQTL, "\n")
        next
    }
}

