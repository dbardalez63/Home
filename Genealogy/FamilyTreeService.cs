namespace FamiliaRodriguez.Genealogy;

public sealed class FamilyTreeService
{
    private readonly Lazy<FamilyTreeSnapshot> _snapshot;
    private readonly IWebHostEnvironment _env;

    public FamilyTreeService(IWebHostEnvironment env)
    {
        _env = env;
        _snapshot = new Lazy<FamilyTreeSnapshot>(Load);
    }

    public FamilyTreeSnapshot GetTree() => _snapshot.Value;

    public Person? GetPerson(string id) =>
        _snapshot.Value.People.TryGetValue(id, out var person) ? person : null;

    public IReadOnlyList<Person> GetPeopleSorted() =>
        _snapshot.Value.People.Values
            .OrderBy(p => p.FullName, StringComparer.CurrentCultureIgnoreCase)
            .ToList();

    public TreeNode BuildDescendantTree(string rootPersonId, int maxDepth = 8)
    {
        var tree = _snapshot.Value;
        if (!tree.People.TryGetValue(rootPersonId, out var root))
        {
            throw new InvalidOperationException($"Persona no encontrada: {rootPersonId}");
        }

        var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        return BuildDescendantNode(root, tree, visited, 0, maxDepth);
    }

    public TreeNode? BuildAncestorTree(string rootPersonId, int maxDepth = 6)
    {
        var tree = _snapshot.Value;
        if (!tree.People.TryGetValue(rootPersonId, out var root))
        {
            return null;
        }

        return BuildAncestorNode(root, tree, 0, maxDepth);
    }

    public IReadOnlyList<(string GenerationLabel, IReadOnlyList<Person> People)> GetGenerationLayers(string rootPersonId)
    {
        var node = BuildDescendantTree(rootPersonId);
        var layers = new SortedDictionary<int, List<Person>>();
        WalkLayers(node, 0, layers);

        return layers
            .Select(kv => (
                kv.Key == 0 ? "Raíz" : kv.Key == 1 ? "Hijos" : kv.Key == 2 ? "Nietos" : kv.Key == 3 ? "Bisnietos" : $"Generación +{kv.Key}",
                (IReadOnlyList<Person>)kv.Value))
            .ToList();
    }

    private static void WalkLayers(TreeNode node, int depth, SortedDictionary<int, List<Person>> layers)
    {
        if (!layers.TryGetValue(depth, out var list))
        {
            list = [];
            layers[depth] = list;
        }

        if (list.All(p => !string.Equals(p.Id, node.Person.Id, StringComparison.OrdinalIgnoreCase)))
        {
            list.Add(node.Person);
        }

        if (node.Spouse is not null &&
            list.All(p => !string.Equals(p.Id, node.Spouse.Id, StringComparison.OrdinalIgnoreCase)))
        {
            list.Add(node.Spouse);
        }

        foreach (var child in node.Children)
        {
            WalkLayers(child, depth + 1, layers);
        }
    }

    private TreeNode BuildDescendantNode(
        Person person,
        FamilyTreeSnapshot tree,
        HashSet<string> visited,
        int depth,
        int maxDepth)
    {
        var node = new TreeNode { Person = person };
        if (!visited.Add(person.Id) || depth >= maxDepth)
        {
            return node;
        }

        var spouseFamilies = tree.Families
            .Where(f =>
                string.Equals(f.HusbandId, person.Id, StringComparison.OrdinalIgnoreCase) ||
                string.Equals(f.WifeId, person.Id, StringComparison.OrdinalIgnoreCase))
            .OrderByDescending(f => f.ChildrenIds.Count)
            .ToList();

        // Prefer the spouse family that has the most children for primary spouse display
        var primary = spouseFamilies.FirstOrDefault();
        if (primary is not null)
        {
            var spouseId = string.Equals(primary.HusbandId, person.Id, StringComparison.OrdinalIgnoreCase)
                ? primary.WifeId
                : primary.HusbandId;
            if (spouseId is not null && tree.People.TryGetValue(spouseId, out var spouse))
            {
                node.Spouse = spouse;
            }
        }

        var childIds = spouseFamilies
            .SelectMany(f => f.ChildrenIds)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Where(id => tree.People.ContainsKey(id))
            .ToList();

        foreach (var childId in childIds)
        {
            node.Children.Add(BuildDescendantNode(tree.People[childId], tree, visited, depth + 1, maxDepth));
        }

        // Also include children from families where person is sole parent (e.g. F19)
        return node;
    }

    private TreeNode BuildAncestorNode(Person person, FamilyTreeSnapshot tree, int depth, int maxDepth)
    {
        var node = new TreeNode { Person = person };
        if (depth >= maxDepth || person.FamilyAsChildId is null)
        {
            return node;
        }

        var family = tree.Families.FirstOrDefault(f =>
            string.Equals(f.Id, person.FamilyAsChildId, StringComparison.OrdinalIgnoreCase));
        if (family is null)
        {
            return node;
        }

        if (family.HusbandId is not null && tree.People.TryGetValue(family.HusbandId, out var father))
        {
            node.Children.Add(BuildAncestorNode(father, tree, depth + 1, maxDepth));
        }

        if (family.WifeId is not null && tree.People.TryGetValue(family.WifeId, out var mother))
        {
            node.Children.Add(BuildAncestorNode(mother, tree, depth + 1, maxDepth));
        }

        return node;
    }

    private FamilyTreeSnapshot Load()
    {
        var candidates = new[]
        {
            Path.Combine(_env.ContentRootPath, "Data", "Gedcom", "Maria-Adela-Rodriguez.ged"),
            Path.Combine(AppContext.BaseDirectory, "Data", "Gedcom", "Maria-Adela-Rodriguez.ged"),
            @"E:\Downloads\Maria-Adela-Rodriguez.ged"
        };

        var path = candidates.FirstOrDefault(File.Exists)
            ?? throw new FileNotFoundException("No se encontró el archivo GEDCOM de Ancestry.");

        var text = File.ReadAllText(path);
        return GedcomParser.Parse(text, "María Adela");
    }
}
