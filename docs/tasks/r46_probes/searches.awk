{ delete v; for(i=2;i<=NF;i++){p=index($i,"="); if(p>0) v[substr($i,1,p-1)]=substr($i,p+1)} st=v["steps"]+0 }
v["tidy"]=="false" { n++; steps+=st; o=(v["outcome"]=="failed")?"failed":"path"; c[o]++; s[o]+=st; if(st>=2000){ln[o]++; ls[o]+=st}
  g=v["gen"]+0; if(g>maxg)maxg=g; gs[g]+=st; gn[g]++;
  if(o=="failed"){ k=v["flow"] " " v["src"] "->" v["sink"]; fk[k]++; fs[k]+=st } }
END { printf "first-routing searches=%d steps=%d | path n=%d steps=%d (long n=%d steps=%d) | failed n=%d steps=%d (long n=%d steps=%d) | generations=%d\n", n,steps,c["path"],s["path"],ln["path"],ls["path"],c["failed"],s["failed"],ln["failed"],ls["failed"],maxg;
  for(k in fk) printf "FAILED %s n=%d steps=%d\n", k, fk[k], fs[k] | "sort -t= -k3 -n -r | head -15" }
