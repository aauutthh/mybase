# git 帮助
----

1. 删除一个远程分支  
  - 确认本地分支与远程分支同步  
    git status  
  - 将远程分支同步到本地  
    git pull  
  - 查看分支  
    git branch -r  
  - 删除本地分支  
    git branch -D gh-page(分支名)  
  - 将变化推送到远程(:gh-page表示推送一个空分支,即删除远程分支)  
    git push origin :gh-page  
