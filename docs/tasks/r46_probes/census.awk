{ delete v; for(i=2;i<=NF;i++){p=index($i,"="); if(p>0) v[substr($i,1,p-1)]=substr($i,p+1)} st=v["steps"]+0; b=v["binding"]+0 }
$1=="trial" { n++; steps+=st;
  if (b < last) pass++; last=b;
  if (v["refused"]=="true") refused++;
  if (st==0) zero++;
  pk=pass "|" b;
  if (!(pk in seenb)) { seenb[pk]=1; bkey=pass "|" v["wanted"]; if (pass>0 && (bkey in tried) && commits==tried[bkey]) dupb[pk]=1; tried[bkey]=commits }
  if (pk in dupb) { dup++; dupsteps+=st }
  if (pass>0) { p2++; p2steps+=st }
  if (st>=2000) { long++; longsteps+=st; if (v["found"]!="true") { longfail++; longfailsteps+=st } }
  if (v["found"]=="true" && v["weight"]!="nil" && v["weight"]+0 < v["best"]+0) { win++; if (st>maxwin) maxwin=st }
}
$1=="commit" { c++; if (v["weight"]!="nil" && v["weight"]+0 < v["before"]+0) { commits++; if (st>maxc) maxc=st } }
END { printf "trials=%d steps=%d | zero_step=%d refused=%d | retry_pass trials=%d steps=%d | same-world repeats trials=%d steps=%d (%.0f%%) | long(>=2000) trials=%d steps=%d (%.0f%%), of them failed trials=%d steps=%d | improving trials=%d max_steps=%d | commits=%d kept=%d max_steps_kept=%d\n", n,steps,zero,refused,p2,p2steps,dup,dupsteps,100*dupsteps/steps,long,longsteps,100*longsteps/steps,longfail,longfailsteps,win,maxwin,c,commits,maxc }
