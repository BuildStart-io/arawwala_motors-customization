import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import DashboardLayout from "@/components/layout/DashboardLayout";
import { useEffectivePlan } from "@/hooks/useEffectivePlan";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Users, Search, Car } from "lucide-react";
import { Input } from "@/components/ui/input";

interface CustomerRow {
  id: string;
  phone_number: string;
  customer_name: string;
  product_name: string | null;
  vehicle_model: string | null;
  updated_at: string;
}

export default function Customers() {
  const [rows, setRows] = useState<CustomerRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const { effectiveUserId } = useEffectivePlan();

  const load = useCallback(async () => {
    if (!effectiveUserId) return;
    setLoading(true);
    try {
      const { data } = await supabase
        .from("leads" as any)
        .select("id, phone_number, customer_name, product_name, vehicle_model, updated_at")
        .eq("user_id", effectiveUserId)
        .order("updated_at", { ascending: false });

      if (data) {
        setRows(data as CustomerRow[]);
      }
    } catch (error) {
      console.error("Failed to load customers:", error);
    } finally {
      setLoading(false);
    }
  }, [effectiveUserId]);

  useEffect(() => {
    load();
  }, [load]);

  const filteredCustomers = rows.filter((r) => {
    const q = search.toLowerCase();
    return (
      (r.customer_name && r.customer_name.toLowerCase().includes(q)) ||
      (r.phone_number && r.phone_number.toLowerCase().includes(q)) ||
      (r.product_name && r.product_name.toLowerCase().includes(q)) ||
      (r.vehicle_model && r.vehicle_model.toLowerCase().includes(q))
    );
  });

  return (
    <DashboardLayout>
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl sm:text-3xl font-bold tracking-tight">Customers</h1>
          <p className="text-muted-foreground text-sm">
            Customer inquiries and requested products
          </p>
        </div>

        <div className="relative max-w-md">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input
            placeholder="Search by name, phone, product, or vehicle..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="pl-9"
          />
        </div>

        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="flex items-center gap-2 text-lg">
              <Users className="h-5 w-5" />
              {filteredCustomers.length} Customer{filteredCustomers.length !== 1 ? "s" : ""}
            </CardTitle>
          </CardHeader>
          <CardContent>
            {loading ? (
              <p className="text-muted-foreground">Loading...</p>
            ) : filteredCustomers.length === 0 ? (
              <p className="text-muted-foreground">No customers found.</p>
            ) : (
              <div className="divide-y rounded-md border">
                {filteredCustomers.map((row) => (
                  <div key={row.id} className="p-4 flex flex-col md:flex-row gap-4 justify-between items-start md:items-center hover:bg-muted/50 transition-colors">
                    <div className="flex-1">
                      <h3 className="font-semibold text-lg">{row.customer_name || "Unknown Customer"}</h3>
                      <p className="text-sm text-muted-foreground">{row.phone_number}</p>
                    </div>
                    
                    <div className="flex-1 flex flex-col gap-2 min-w-[200px]">
                      <div className="flex items-center gap-2 text-sm">
                        <span className="font-medium bg-primary/10 text-primary px-2 py-0.5 rounded text-xs uppercase tracking-wide">Product</span>
                        <span className={row.product_name ? "text-foreground font-medium" : "text-muted-foreground italic"}>
                          {row.product_name || "Not provided"}
                        </span>
                      </div>
                      
                      <div className="flex items-center gap-2 text-sm">
                        <span className="font-medium bg-secondary text-secondary-foreground px-2 py-0.5 rounded text-xs uppercase tracking-wide">Vehicle</span>
                        <span className={row.vehicle_model ? "text-foreground font-medium" : "text-muted-foreground italic"}>
                          {row.vehicle_model || "Not provided"}
                        </span>
                      </div>
                    </div>
                    
                    <div className="text-xs text-muted-foreground hidden md:block">
                      Last updated: {new Date(row.updated_at).toLocaleDateString()}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </DashboardLayout>
  );
}
