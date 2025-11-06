Cet outil à pour intérêt de faire un diff entre 2 zip
Il fonctionne sur le principe que 2 fichiers sont identique s'ils ont le même nom et la même taille (le contenu d'un fichier n'est pas vérifier)
Fonctionne de manière récurcive, dans le principe :
Ouvre le zip
Pour chaque fichier / dossier :
Si c'est un fichier : 
	vérifie que le nom existe au même endroit dans l'autre zip
		si c'est le cas, vérifie la taille, si celle-ci est différente, ajoute ce fichier dans la liste des différences
		Si ce n'est pas le cas, ajoute ce fichier dans la liste des fichiers présent dans un zip mais pas dans l'autre (idem du zip2 vers le zip1)
Si c'est un dossier / zip / ear / jar ... réapplique la recherche à ce niveau

Axe d'amélioration :
tester / faire en sorte de pouvoir ouvrir autre chose que des zip
Ajouter 2 paramètre pour les numéros de versions puisque bien que ceux-ci soit différent l'utilité est de comparer 2 versions différentes