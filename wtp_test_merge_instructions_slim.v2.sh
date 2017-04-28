#!/bin/sh

# make a new folder and put this file inside it. 
# Then execute it. 
#
# This script rewrites history for each of the four repositories, 
# specifically, to make ALL commits of the repos believe they were 
# always in a subfolder of the repository. 
#  Examples:
#  - pom.xml from webtools.common repo is rewritten to believe it always
#    lived inside webtools.common.all repo at webtools.common/pom.xml   
#    (ie rewrote all history so pom.xml always was webtools.common/pom.xml)
#  - pom.xml from webtools.common.tests repo is rewritten to believe it always
#    lived inside webtools.common.all repo at webtools.common.tests/pom.xml
#    (ie rewrote all history so pom.xml always was webtools.common.tests/pom.xml)
# etc etc etc. 
#
# This changes all hashes of all previous commits, tags, branches, etc
# but keeps them otherwise identical.
# 
# The script then backs up these 4 rewritten repos to a temporary folder
# named 'intermediary' for use later in the script. 
# 
# The script then rebuilds all branches and tags for a merged repo.
# This is a bit of a challenge, because the different repos may share,
# or not share, a given tag or branch name. In the event two repos
# share a branch or tag id, we should merge those two together. 
# 
# It would be near impossible, short of going commit-by-commit, 
# to re-create all 4 repos at the time of a given tag that exists
# only in one repo, so for such branches or tags, we keep just 1
# of the repos in that given tag. 
#
# However, this would cause the root of the repo to change repeatedly
# from having subfolders to not having subfolders, and this would be
# disruptive or confusing to the user. 
# Ex:
#  - repo at master: 'ls' returns webtools.common  webtools.common.fproj  webtools.common.snippets  webtools.common.tests
#  - user does git checkout for branch name 'TEMP_M4'
#  - 'ls' now returns 'plugins' only.  
# 
# This is a problem, because the user won't know (without inspection)
# which pre-merge repo this tag or branch existed in... basically, 
# they won't know what they're browsing. The main directory structure
# with 4 subdirs should be maintained in all tags and branches ideally. 
# So this script accomplishes that goal, at the expense of 
# changing hashes, and rewriting history to make the files
# think they always lived in subfolders. 
#
# I hope this isn't too much of a drawback. It will most likely
# invalidate a lot of PRs that haven't been accepted yet :( 
# So that's definitely a problem. 
#
# The script takes about a half hour +/- 10min to run. 

START_TIME=`date +%s`

# lets forget this is a git repo... it's just a folder with some patches now
rm -rf .git

# set some vars, users should change this
NEW_REPO_NAME="webtools.common.all"
README_MD_CONTENT="webtools commons in one repository"
REPO_LIST=("http://git.eclipse.org/gitroot/webtools-common/webtools.common.fproj.git"
    "http://git.eclipse.org/gitroot/webtools-common/webtools.common.git"
    "http://git.eclipse.org/gitroot/webtools-common/webtools.common.snippets.git"
    "http://git.eclipse.org/gitroot/webtools-common/webtools.common.tests.git")

# Users should override this function if they have anything they want to change
# after a clone, but before we begin processing
postClone() {
    echo "Inside postClone"
    cd ./webtools.common.fproj/
    git branch R3_8_maintenance
    cd ../
    cd ./webtools.common.snippets/
    git branch R3_8_maintenance
    cd ../
    cd ./webtools.common.tests/
    git branch R3_8_maintenance
    cd ../
}

applyPatches() {
    echo "Hello"
}




# set our local pull command depending on git version
verlte() {
    [  "$1" = "`echo -e "$1\n$2" | sort -V | head -n1`" ]
}

verlt() {
    [ "$1" = "$2" ] && return 1 || verlte $1 $2
}
GIT_VERSION=`git version | cut -f 3 -d " "`
verlte $GIT_VERSION 2.9.0 && ALLOW_PULL_FLAG=false || ALLOW_PULL_FLAG=true

if $ALLOW_PULL_FLAG
then
   LOCAL_PULL_CMD="git pull --no-edit --allow-unrelated-histories"
else
   LOCAL_PULL_CMD="git pull --no-edit "
fi


# begin making the folders we'll work in
rm -rf workingDirectory
mkdir workingDirectory
cd workingDirectory


mkdir testoutput
mkdir intermediate

mkdir $NEW_REPO_NAME
cd $NEW_REPO_NAME

# do a fresh clone of the four repos
for var in "${REPO_LIST[@]}"
do
    git clone $var
done

# run the postClone hook
postClone


MAIN_FOLDERS=($(ls -1))
for var in "${MAIN_FOLDERS[@]}"
do
   cd $var
   echo ""
   echo "Rewriting history for " $var " so it thinks it was always in a subfolder"
   git filter-branch --index-filter \
    'git ls-files -s | sed "s-\t-&'$var'/-" |
     GIT_INDEX_FILE=$GIT_INDEX_FILE.new \
     git update-index --index-info &&
     mv $GIT_INDEX_FILE.new $GIT_INDEX_FILE' \
     --tag-name-filter 'cat'\
     -- --all
   cd ../
done

# Back up all tags and keys
echo ""
echo "Back up tags and branches with rewritten history to use later"
for var2 in "${MAIN_FOLDERS[@]}"
do
   cd $var2
   git for-each-ref > ../../testoutput/$var2.txt
   cd ../
done


# Back up the four repos with rewritten history
echo ""
echo "Back up the re-written repos for use later"
cp -R * ../intermediate


# Merge them into one repo
# The resultant repo will look like as if n trees
# were merged together. n-1 of those trees are 
# the individual subfolders. The remaining nth 
# is a README.md commit. 

echo "\nInitialize new container repo"
git init

echo "# $NEW_REPO_NAME" > README.md
echo "$README_MD_CONTENT" >> README.md
git add README.md
git commit -a -m "Initial Commit for unified repository"

INITIALHASH=`git log -p | grep "^commit" | head -n 1 | cut -f 2 -d " "`
echo $INITIALHASH


echo ""
echo "Merge in the n rewritten projects, with generic commit messages"
for var3 in "${MAIN_FOLDERS[@]}"
do
   $LOCAL_PULL_CMD $var3
done


FINALHASH=`git log -p | grep "^commit" | head -n 1 | cut -f 2 -d " "`
echo $FINALHASH


# Let's save the tags for each folder
echo ""
echo "Building a model of existing tags to rebuild them later"
echo "If some tags are the same in more than one repo, we will need"
echo "build a merge commit to store as the tag."
sleep 5


# Map of unique tags
unset ALL_UNIQUE_TAGS
unset PROJECT_SPECIFIC_TAGS
declare -A ALL_UNIQUE_TAGS
declare -A PROJECT_SPECIFIC_TAGS

for var4 in "${MAIN_FOLDERS[@]}"
do
   cd $var4
   COMPILED=""
   LOCAL_TAGS=`git for-each-ref | grep -v "origin" | grep "tags" | cut -f 2 -d " " | cut -f 2 -d$'\t' | cut -f 3 -d "/"`
   LOCAL_TAGS_ARR=($LOCAL_TAGS)
   for onetag in "${LOCAL_TAGS_ARR[@]}"
   do
      COMMIT_ID=`git log ${onetag}  | head -n 1 | cut -f 2 -d " "`
      KEQV="$onetag:$COMMIT_ID"
      TMP1="$KEQV,$COMPILED"
      COMPILED="$TMP1"
      ALL_UNIQUE_TAGS[${onetag}]="x"
   done
   PROJECT_SPECIFIC_TAGS[${var4}]="$COMPILED"
   cd ../
done

echo ""
echo "Starting to rebuild all the tags."
echo "Tags that exist in only one repo will, when checked out, include only"
echo "the one subfolder, since we can't know what the others looked like at"
echo "that time. Tags existing in two or more repos will include only those subfolders."
echo "number of tags: " ${#ALL_UNIQUE_TAGS[@]}
sleep 10



# set up a working branch
git checkout -b test
rm -rf *
git reset --hard $INITIALHASH

# print out the list of unique tags, just to make sure we got it
for key in ${!ALL_UNIQUE_TAGS[@]}; do
    rm -rf *
    git reset --hard $INITIALHASH

    for folder in "${MAIN_FOLDERS[@]}"
    do
       TMP_TAGS=${PROJECT_SPECIFIC_TAGS[${folder}]}
       FOUND=`echo $TMP_TAGS | sed 's/,/\n/g' | grep "^$key:" | cut -f 2 -d ":"`
       if [ -z "$FOUND" ]
       then
           echo "Tag does not exist in " $folder
       else
           echo "Tag " $key " does exist in " $folder " and has commit " $FOUND
           cd ../intermediate/$folder
           git checkout $FOUND
           cd ../../$NEW_REPO_NAME
           $LOCAL_PULL_CMD ../intermediate/$folder
       fi
    done

    git tag $key
#    sleep 5

done




#
# All tags are saved, lets move on to branches
#

cd ../intermediate/
UNIQ_BRANCHES=`ls -1 | awk '{ print "cd " $0 "; git branch -a  | grep -v HEAD | grep -v master | cut -f 3 -d \"/\"; cd ../";}' | sh | sort | uniq`
UNIQ_BRANCHES_ARR=($UNIQ_BRANCHES)
cd ../$NEW_REPO_NAME/


for var in "${UNIQ_BRANCHES_ARR[@]}"
do
   git checkout -b $var
   git reset --hard $INITIALHASH

   for folder in "${MAIN_FOLDERS[@]}"
   do
       rm -rf $folder
   done

   cd ../intermediate

   for folder in "${MAIN_FOLDERS[@]}"
   do
       cd $folder
       FOLDER_HAS=`git branch -a | grep $var`
       if [ -z "$FOLDER_HAS" ]
       then
          echo "$folder does not have branch $var. Do nothing"
          cd ..
       else
          echo "$folder HAS branch $var. Process it."
          git checkout $var
          cd ../../$NEW_REPO_NAME/
          $LOCAL_PULL_CMD ../intermediate/$folder
          cd ../intermediate/
       fi
   done
   cd ../$NEW_REPO_NAME/
done



# cleanup our 'test' branch, created to create all tags
git branch -D test


# Push to my repo for backup.

#repo=mine
#repourl=git@github.com:robstryker/$NEW_REPO_NAME.git

#git remote add $repo $repourl
#git checkout master
#git push --force $repo master


# push all branches
#for var in "${UNIQ_BRANCHES_ARR[@]}"
#do
#   git checkout $var
#   git push $repo $var
#done

#git push $repo --tags


# apply some patches
applyPatches

END_TIME=`date +%s`
EXEC_TIME=$((END_TIME-START_TIME))
echo $EXEC_TIME " seconds execution time"
