import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Plus, Trash2, X, ChevronDown, ChevronRight, ImagePlus, Loader2 } from "lucide-react";
import { Switch } from "@/components/ui/switch";
import { useState } from "react";
import { uploadMedia, deleteMedia } from "@/lib/mediaStorage";
import { useToast } from "@/hooks/use-toast";

export interface SubVariantOption {
  label: string;
  price: number;
}

export interface SubVariant {
  name: string;
  required: boolean;
  options: SubVariantOption[];
}

export interface VariationOption {
  label: string;
  price: number;
  images?: string[];
  subVariants?: SubVariant[];
}

export interface Variation {
  name: string;
  options: VariationOption[];
}

interface VariationEditorProps {
  variations: Variation[];
  onChange: (variations: Variation[]) => void;
  hasVariationImages?: boolean;
  onHasVariationImagesChange?: (enabled: boolean) => void;
}

export default function VariationEditor({
  variations,
  onChange,
  hasVariationImages = false,
  onHasVariationImagesChange,
}: VariationEditorProps) {
  const { toast } = useToast();
  const [uploadingKey, setUploadingKey] = useState<string | null>(null);
  const [expandedOptions, setExpandedOptions] = useState<Record<string, boolean>>({});

  const toggleExpand = (key: string) => {
    setExpandedOptions(prev => ({ ...prev, [key]: !prev[key] }));
  };

  const addVariation = () => {
    onChange([...variations, { name: "", options: [{ label: "", price: 0 }] }]);
  };

  const removeVariation = (index: number) => {
    onChange(variations.filter((_, i) => i !== index));
  };

  const updateVariationName = (index: number, name: string) => {
    const updated = [...variations];
    updated[index] = { ...updated[index], name };
    onChange(updated);
  };

  const addOption = (varIndex: number) => {
    const updated = [...variations];
    updated[varIndex] = {
      ...updated[varIndex],
      options: [...updated[varIndex].options, { label: "", price: 0 }],
    };
    onChange(updated);
  };

  const removeOption = (varIndex: number, optIndex: number) => {
    const updated = [...variations];
    updated[varIndex] = {
      ...updated[varIndex],
      options: updated[varIndex].options.filter((_, i) => i !== optIndex),
    };
    onChange(updated);
  };

  const updateOption = (varIndex: number, optIndex: number, field: "label" | "price", value: string) => {
    const updated = [...variations];
    const option = { ...updated[varIndex].options[optIndex] };
    if (field === "price") {
      option.price = parseFloat(value) || 0;
    } else {
      option.label = value;
    }
    updated[varIndex] = {
      ...updated[varIndex],
      options: updated[varIndex].options.map((o, i) => (i === optIndex ? option : o)),
    };
    onChange(updated);
  };

  const handleOptionImagesUpload = async (
    varIndex: number,
    optIndex: number,
    e: React.ChangeEvent<HTMLInputElement>
  ) => {
    const files = e.target.files;
    if (!files || files.length === 0) return;

    const key = `${varIndex}-${optIndex}`;
    setUploadingKey(key);

    try {
      const uploaded: string[] = [];
      for (const file of Array.from(files)) {
        if (!file.type.startsWith("image/")) continue;
        if (file.size > 5 * 1024 * 1024) {
          toast({
            title: "File too large",
            description: `${file.name} exceeds 5MB limit.`,
            variant: "destructive",
          });
          continue;
        }
        const url = await uploadMedia(file, "products");
        uploaded.push(url);
      }

      if (uploaded.length > 0) {
        const updated = [...variations];
        const option = { ...updated[varIndex].options[optIndex] };
        option.images = [...(option.images || []), ...uploaded];
        updated[varIndex] = {
          ...updated[varIndex],
          options: updated[varIndex].options.map((o, i) => (i === optIndex ? option : o)),
        };
        onChange(updated);
      }
    } catch (error: any) {
      toast({
        title: "Upload failed",
        description: error.message,
        variant: "destructive",
      });
    } finally {
      setUploadingKey(null);
      e.target.value = "";
    }
  };

  const removeOptionImage = (varIndex: number, optIndex: number, imgIndex: number) => {
    const updated = [...variations];
    const option = { ...updated[varIndex].options[optIndex] };
    const currentImages = option.images || [];
    const urlToRemove = currentImages[imgIndex];
    option.images = currentImages.filter((_, i) => i !== imgIndex);
    updated[varIndex] = {
      ...updated[varIndex],
      options: updated[varIndex].options.map((o, i) => (i === optIndex ? option : o)),
    };
    onChange(updated);
    if (urlToRemove) {
      deleteMedia(urlToRemove).catch(() => {});
    }
  };

  // Sub-variant helpers
  const addSubVariant = (varIndex: number, optIndex: number) => {
    const updated = [...variations];
    const option = { ...updated[varIndex].options[optIndex] };
    option.subVariants = [...(option.subVariants || []), { name: "", required: false, options: [{ label: "", price: 0 }] }];
    updated[varIndex] = {
      ...updated[varIndex],
      options: updated[varIndex].options.map((o, i) => (i === optIndex ? option : o)),
    };
    onChange(updated);
    toggleExpand(`${varIndex}-${optIndex}`);
  };

  const removeSubVariant = (varIndex: number, optIndex: number, subVarIndex: number) => {
    const updated = [...variations];
    const option = { ...updated[varIndex].options[optIndex] };
    option.subVariants = (option.subVariants || []).filter((_, i) => i !== subVarIndex);
    updated[varIndex] = {
      ...updated[varIndex],
      options: updated[varIndex].options.map((o, i) => (i === optIndex ? option : o)),
    };
    onChange(updated);
  };

  const updateSubVariantName = (varIndex: number, optIndex: number, subVarIndex: number, name: string) => {
    const updated = [...variations];
    const option = { ...updated[varIndex].options[optIndex] };
    const subVariants = [...(option.subVariants || [])];
    subVariants[subVarIndex] = { ...subVariants[subVarIndex], name };
    option.subVariants = subVariants;
    updated[varIndex] = {
      ...updated[varIndex],
      options: updated[varIndex].options.map((o, i) => (i === optIndex ? option : o)),
    };
    onChange(updated);
  };

  const addSubOption = (varIndex: number, optIndex: number, subVarIndex: number) => {
    const updated = [...variations];
    const option = { ...updated[varIndex].options[optIndex] };
    const subVariants = [...(option.subVariants || [])];
    subVariants[subVarIndex] = {
      ...subVariants[subVarIndex],
      options: [...subVariants[subVarIndex].options, { label: "", price: 0 }],
    };
    option.subVariants = subVariants;
    updated[varIndex] = {
      ...updated[varIndex],
      options: updated[varIndex].options.map((o, i) => (i === optIndex ? option : o)),
    };
    onChange(updated);
  };

  const removeSubOption = (varIndex: number, optIndex: number, subVarIndex: number, subOptIndex: number) => {
    const updated = [...variations];
    const option = { ...updated[varIndex].options[optIndex] };
    const subVariants = [...(option.subVariants || [])];
    subVariants[subVarIndex] = {
      ...subVariants[subVarIndex],
      options: subVariants[subVarIndex].options.filter((_, i) => i !== subOptIndex),
    };
    option.subVariants = subVariants;
    updated[varIndex] = {
      ...updated[varIndex],
      options: updated[varIndex].options.map((o, i) => (i === optIndex ? option : o)),
    };
    onChange(updated);
  };

  const updateSubOption = (
    varIndex: number, optIndex: number, subVarIndex: number, subOptIndex: number,
    field: "label" | "price", value: string
  ) => {
    const updated = [...variations];
    const option = { ...updated[varIndex].options[optIndex] };
    const subVariants = [...(option.subVariants || [])];
    const subOpt = { ...subVariants[subVarIndex].options[subOptIndex] };
    if (field === "price") {
      subOpt.price = parseFloat(value) || 0;
    } else {
      subOpt.label = value;
    }
    subVariants[subVarIndex] = {
      ...subVariants[subVarIndex],
      options: subVariants[subVarIndex].options.map((o, i) => (i === subOptIndex ? subOpt : o)),
    };
    option.subVariants = subVariants;
    updated[varIndex] = {
      ...updated[varIndex],
      options: updated[varIndex].options.map((o, i) => (i === optIndex ? option : o)),
    };
    onChange(updated);
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Label className="text-sm font-semibold">Variations</Label>
          {onHasVariationImagesChange && (
            <div className="flex items-center space-x-2 border-l pl-3">
              <Switch
                id="toggle-variation-photos"
                checked={hasVariationImages}
                onCheckedChange={onHasVariationImagesChange}
              />
              <Label htmlFor="toggle-variation-photos" className="text-xs text-muted-foreground cursor-pointer font-normal">
                Upload photos to variations
              </Label>
            </div>
          )}
        </div>
        <Button type="button" variant="outline" size="sm" onClick={addVariation}>
          <Plus className="mr-1 h-3 w-3" />
          Add Variation
        </Button>
      </div>

      {variations.length === 0 && (
        <p className="text-sm text-muted-foreground">No variations. Add one to set variation-based pricing.</p>
      )}

      {variations.map((variation, varIndex) => (
        <div key={varIndex} className="rounded-lg border p-4 space-y-3">
          <div className="flex items-center gap-2">
            <Input
              placeholder="e.g. Size, Color"
              value={variation.name}
              onChange={(e) => updateVariationName(varIndex, e.target.value)}
              className="flex-1"
            />
            <Button type="button" variant="ghost" size="icon" onClick={() => removeVariation(varIndex)}>
              <Trash2 className="h-4 w-4 text-destructive" />
            </Button>
          </div>

          <div className="space-y-2 pl-4">
            <div className="grid grid-cols-[20px_1fr_100px_32px_32px] gap-2 text-xs font-medium text-muted-foreground">
              <span />
              <span>Option</span>
              <span>Price</span>
              <span />
              <span />
            </div>
            {variation.options.map((option, optIndex) => {
              const expandKey = `${varIndex}-${optIndex}`;
              const isExpanded = expandedOptions[expandKey];
              const hasSubVariants = option.subVariants && option.subVariants.length > 0;

              return (
                <div key={optIndex} className="space-y-2">
                  <div className="grid grid-cols-[20px_1fr_100px_32px_32px] gap-2 items-center">
                    <button
                      type="button"
                      onClick={() => toggleExpand(expandKey)}
                      className="flex items-center justify-center h-8 w-5 text-muted-foreground hover:text-foreground"
                    >
                      {hasSubVariants || isExpanded ? (
                        isExpanded ? <ChevronDown className="h-3 w-3" /> : <ChevronRight className="h-3 w-3" />
                      ) : (
                        <span className="h-3 w-3" />
                      )}
                    </button>
                    <Input
                      placeholder="e.g. Small, Red"
                      value={option.label}
                      onChange={(e) => updateOption(varIndex, optIndex, "label", e.target.value)}
                      className="h-8 text-sm"
                    />
                    <Input
                      type="number"
                      step="0.01"
                      placeholder="0.00"
                      value={option.price || ""}
                      onChange={(e) => updateOption(varIndex, optIndex, "price", e.target.value)}
                      className="h-8 text-sm"
                    />
                    <Button
                      type="button"
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8"
                      title="Add sub-variant"
                      onClick={() => addSubVariant(varIndex, optIndex)}
                    >
                      <Plus className="h-3 w-3" />
                    </Button>
                    <Button
                      type="button"
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8"
                      onClick={() => removeOption(varIndex, optIndex)}
                      disabled={variation.options.length <= 1}
                    >
                      <X className="h-3 w-3" />
                    </Button>
                  </div>

                  {/* Variation Photos for this option */}
                  {hasVariationImages && (
                    <div className="flex flex-wrap items-center gap-2 pl-7 pt-1 pb-1">
                      {(option.images || []).map((imgUrl, imgIdx) => (
                        <div
                          key={imgIdx}
                          className="relative group w-12 h-12 rounded-md border overflow-hidden bg-muted flex-shrink-0"
                        >
                          <img
                            src={imgUrl}
                            alt={`${option.label || "Variation"} photo ${imgIdx + 1}`}
                            className="w-full h-full object-cover"
                          />
                          <button
                            type="button"
                            onClick={() => removeOptionImage(varIndex, optIndex, imgIdx)}
                            className="absolute top-0.5 right-0.5 bg-destructive text-destructive-foreground rounded-full p-0.5 opacity-0 group-hover:opacity-100 transition-opacity"
                            title="Remove photo"
                          >
                            <X className="h-3 w-3" />
                          </button>
                        </div>
                      ))}

                      <label className="w-12 h-12 rounded-md border-2 border-dashed border-muted-foreground/30 flex flex-col items-center justify-center cursor-pointer hover:border-primary/50 transition-colors text-muted-foreground hover:text-foreground flex-shrink-0">
                        {uploadingKey === `${varIndex}-${optIndex}` ? (
                          <Loader2 className="h-4 w-4 animate-spin" />
                        ) : (
                          <>
                            <ImagePlus className="h-3.5 w-3.5" />
                            <span className="text-[9px] mt-0.5 font-medium">+ Photo</span>
                          </>
                        )}
                        <input
                          type="file"
                          accept="image/jpeg,image/png,image/webp"
                          multiple
                          className="hidden"
                          disabled={uploadingKey === `${varIndex}-${optIndex}`}
                          onChange={(e) => handleOptionImagesUpload(varIndex, optIndex, e)}
                        />
                      </label>
                    </div>
                  )}

                  {/* Sub-variants */}
                  {isExpanded && option.subVariants && option.subVariants.length > 0 && (
                    <div className="ml-7 space-y-3">
                      {option.subVariants.map((subVar, subVarIndex) => (
                        <div key={subVarIndex} className="rounded border border-dashed p-3 space-y-2 bg-muted/30">
                          <div className="flex items-center gap-2">
                            <Input
                              placeholder="Sub-variant name (e.g. Flavor, Topping)"
                              value={subVar.name}
                              onChange={(e) => updateSubVariantName(varIndex, optIndex, subVarIndex, e.target.value)}
                              className="flex-1 h-7 text-xs"
                            />
                            <div className="flex items-center gap-1">
                              <Switch
                                checked={subVar.required ?? false}
                                onCheckedChange={(checked) => {
                                  const updated = [...variations];
                                  const opt = { ...updated[varIndex].options[optIndex] };
                                  const subs = [...(opt.subVariants || [])];
                                  subs[subVarIndex] = { ...subs[subVarIndex], required: checked };
                                  opt.subVariants = subs;
                                  updated[varIndex] = { ...updated[varIndex], options: updated[varIndex].options.map((o, i) => (i === optIndex ? opt : o)) };
                                  onChange(updated);
                                }}
                                className="scale-75"
                              />
                              <span className="text-[10px] text-muted-foreground whitespace-nowrap">Required</span>
                            </div>
                            <Button
                              type="button"
                              variant="ghost"
                              size="icon"
                              className="h-7 w-7"
                              onClick={() => removeSubVariant(varIndex, optIndex, subVarIndex)}
                            >
                              <Trash2 className="h-3 w-3 text-destructive" />
                            </Button>
                          </div>

                          <div className="space-y-1 pl-2">
                            <div className="grid grid-cols-[1fr_80px_24px] gap-1 text-[10px] font-medium text-muted-foreground">
                              <span>Sub-option</span>
                              <span>Price</span>
                              <span />
                            </div>
                            {subVar.options.map((subOpt, subOptIndex) => (
                              <div key={subOptIndex} className="grid grid-cols-[1fr_80px_24px] gap-1 items-center">
                                <Input
                                  placeholder="e.g. Vanilla"
                                  value={subOpt.label}
                                  onChange={(e) => updateSubOption(varIndex, optIndex, subVarIndex, subOptIndex, "label", e.target.value)}
                                  className="h-7 text-xs"
                                />
                                <Input
                                  type="number"
                                  step="0.01"
                                  placeholder="0.00"
                                  value={subOpt.price || ""}
                                  onChange={(e) => updateSubOption(varIndex, optIndex, subVarIndex, subOptIndex, "price", e.target.value)}
                                  className="h-7 text-xs"
                                />
                                <Button
                                  type="button"
                                  variant="ghost"
                                  size="icon"
                                  className="h-7 w-7"
                                  onClick={() => removeSubOption(varIndex, optIndex, subVarIndex, subOptIndex)}
                                  disabled={subVar.options.length <= 1}
                                >
                                  <X className="h-3 w-3" />
                                </Button>
                              </div>
                            ))}
                            <Button
                              type="button"
                              variant="ghost"
                              size="sm"
                              className="text-[10px] h-6"
                              onClick={() => addSubOption(varIndex, optIndex, subVarIndex)}
                            >
                              <Plus className="mr-1 h-2 w-2" />
                              Add Sub-option
                            </Button>
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              );
            })}
            <Button type="button" variant="ghost" size="sm" className="text-xs" onClick={() => addOption(varIndex)}>
              <Plus className="mr-1 h-3 w-3" />
              Add Option
            </Button>
          </div>
        </div>
      ))}
    </div>
  );
}
